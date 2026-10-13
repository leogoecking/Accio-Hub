#!/usr/bin/env ruby
require "bundler/setup"
require "tmpdir"
require "open3"
require "json"
require "fileutils"
require "timeout"
root = File.expand_path("..", __dir__)
evidence = ENV.fetch("ACCIO_QA_EVIDENCE", File.expand_path("../../docs/assets/p1.2d3", __dir__))
FileUtils.mkdir_p(evidence)
results = {}
Dir.mktmpdir("p12d3-contract-", File.join(root, "tmp")) do |directory|
  env = { "RAILS_ENV" => "test", "ACCIO_DATABASE_PATH" => File.join(directory, "synthetic.sqlite3"), "D3_WORKSPACE" => directory }
  runner = File.join(directory, "runner.rb")
  File.write(runner, <<~'CODE')
    require "json"
    require "timeout"
    directory = ENV.fetch("D3_WORKSPACE")
    raise "Synthetic only" unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database.start_with?(directory + "/")
    mode = ENV.fetch("D3_MODE")
    if mode == "seed"
      password = SecureRandom.hex(20)
      user = User.create!(email_address: "references@example.test", password: password)
      AppearancePreferences.new(user).bootstrap(legacy: nil, raw: nil)
      project = user.projects.create!(uid: "42/á?%#项目", name: "Origem QA")
      user.projects.create!(uid: "target", name: "Destino QA")
      File.write(File.join(directory, "credential.json"), JSON.generate({ password: password }), mode: "w", perm: 0o600)
      File.write(File.join(directory, "intent"), ReferenceCommands.new(user).issue(context: project.uid))
      exit
    end
    user = User.first
    project = user.projects.first
    reference = user.project_references.first
    if mode == "worker"
      index = ENV.fetch("D3_WORKER")
      operation = ENV.fetch("D3_OPERATION")
      require "action_dispatch/testing/integration"
      client = ActionDispatch::Integration::Session.new(Rails.application)
      client.host! "localhost"
      client.post "/session", params: { email_address: user.email_address, password: JSON.parse(File.read(File.join(directory, "credential.json"))).fetch("password") }, headers: { "REMOTE_ADDR" => "127.0.0.1" }
      version = reference&.lock_version
      parent_version = project.lock_version
      File.write(File.join(directory, "ready-#{index}"), "ready")
      Timeout.timeout(25) { sleep 0.01 until File.exist?(File.join(directory, "release")) }
      headers = { "REMOTE_ADDR" => "127.0.0.1" }
      case operation
      when "create", "incompatible"
        title = operation == "incompatible" ? "Race #{index}" : "Race QA"
        client.post "/projects/#{project.to_param}/references", params: { intent: File.read(File.join(directory, "intent")), reference: { title: title, kind: "link", url: "https://example.test", description: "QA" } }, as: :json, headers: headers
      when "edit"
        client.patch "/projects/#{project.to_param}/references/#{reference.to_param}", params: { version: version, reference: { title: "Edit #{index}", kind: "link", url: "https://example.test", description: "QA" } }, as: :json, headers: headers
      when "archive_edit", "archive_create"
        if index == "0"
          client.patch "/projects/#{project.to_param}/command", params: { version: parent_version, operation: "archive" }, as: :json, headers: headers
        elsif operation == "archive_create"
          client.post "/projects/#{project.to_param}/references", params: { intent: File.read(File.join(directory, "intent")), reference: { title: "Concurrent new", kind: "material", description: "QA" } }, as: :json, headers: headers
        else
          client.patch "/projects/#{project.to_param}/references/#{reference.to_param}", params: { version: version, reference: { title: "Concurrent", kind: "link", url: "https://example.test" } }, as: :json, headers: headers
        end
      end
      raise "Unexpected HTTP #{client.response.status}: #{client.response.body[0,200]}" unless [ 200, 409 ].include?(client.response.status)
      puts JSON.generate({ worker: index, http: client.response.status, parent_archived: project.reload.status == "archived", reference_title: reference&.reload&.title })
    elsif mode == "reset"
      project.restore! if project.status == "archived"
      File.write(File.join(directory, "intent"), ReferenceCommands.new(user).issue(context: project.uid))
    elsif mode == "counts"
      puts JSON.generate({ references: user.project_references.count, unique_uids: user.project_references.distinct.count(:uid), parent_version: project.lock_version })
    elsif mode == "snapshot"
      value = { references: user.project_references.order(:id).map(&:attributes), projects: user.projects.order(:id).map(&:attributes), preferences: AppearancePreferences.new(user).read }
      File.write(File.join(directory, "snapshot.json"), JSON.generate(value.as_json))
      puts JSON.generate({ references: ProjectReference.count, triggers: ProjectReference.connection.select_value("SELECT count(*) FROM sqlite_master WHERE type='trigger'"), foreign_keys: ProjectReference.connection.select_all("PRAGMA foreign_key_check").empty? })
    elsif mode == "reopen"
      value = { references: user.project_references.order(:id).map(&:attributes), projects: user.projects.order(:id).map(&:attributes), preferences: AppearancePreferences.new(user).read }
      raise "Reopen mismatch" unless JSON.parse(File.read(File.join(directory, "snapshot.json"))) == JSON.parse(JSON.generate(value.as_json))
      puts JSON.generate({ new_process_identical: true })
    elsif mode == "busy_http"
      require "action_dispatch/testing/integration"
      client = ActionDispatch::Integration::Session.new(Rails.application); client.host! "localhost"
      client.post "/session", params: { email_address: user.email_address, password: JSON.parse(File.read(File.join(directory, "credential.json"))).fetch("password") }, headers: { "REMOTE_ADDR" => "127.0.0.1" }
      ProjectReference.connection.execute("PRAGMA busy_timeout=50")
      File.write(File.join(directory, "busy-ready"), "ready")
      Timeout.timeout(25) { sleep 0.01 until File.exist?(File.join(directory, "held")) }
      client.patch "/projects/#{project.to_param}/references/#{reference.to_param}", params: { version: reference.lock_version, reference: { title: "Busy blocked" } }, as: :json, headers: { "REMOTE_ADDR" => "127.0.0.1" }
      raise "Expected 503" unless client.response.status == 503
      puts JSON.generate({ writer_contention_http: 503 })
    elsif mode == "holder"
      Timeout.timeout(25) { sleep 0.01 until File.exist?(File.join(directory, "busy-ready")) }
      ProjectReference.connection.execute("BEGIN IMMEDIATE")
      File.write(File.join(directory, "held"), "held")
      Timeout.timeout(25) { sleep 0.01 until File.exist?(File.join(directory, "writer-release")) }
      ProjectReference.connection.execute("ROLLBACK")
    end
  CODE
  run = ->(command, more = {}) do
    output, errors, status = Open3.capture3(env.merge(more), *command, chdir: root)
    raise "Synthetic command failed: #{command.join(' ')}\n#{output}\n#{errors}" unless status.success?
    output
  end
  call = ->(mode) { run.call([ "bin/rails", "runner", runner ], "D3_MODE" => mode) }
  run.call([ "bin/rails", "db:schema:load" ])
  tests = run.call([ "bin/rails", "test" ])
  File.write(File.join(evidence, "rails-tests.log"), tests)
  results[:suite] = tests.lines.find { |line| line.include?(" runs, ") }&.strip
  call.call("seed")
  %w[create incompatible edit archive_edit archive_create].each do |operation|
    call.call("reset") unless operation == "create"
    before = JSON.parse(call.call("counts"))
    %w[ready-0 ready-1 release].each { |name| FileUtils.rm_f(File.join(directory, name)) }
    workers = 2.times.map do |index|
      log = File.open(File.join(directory, "worker-#{index}.log"), "w")
      pid = Process.spawn(env.merge("D3_MODE" => "worker", "D3_OPERATION" => operation, "D3_WORKER" => index.to_s), "bin/rails", "runner", runner, chdir: root, out: log, err: log)
      log.close; pid
    end
    remaining = workers.dup
    begin
      Timeout.timeout(35) { sleep 0.01 until 2.times.all? { |i| File.exist?(File.join(directory, "ready-#{i}")) } }
      File.write(File.join(directory, "release"), "go")
      rows = workers.each_with_index.map do |pid, i|
        _, status = Timeout.timeout(35) { Process.wait2(pid) }; remaining.delete(pid)
        output = File.read(File.join(directory, "worker-#{i}.log"))
        raise output unless status.success?
        JSON.parse(output)
      end
      expected = operation == "create" ? [ 200, 200 ] : [ 200, 409 ]
      raise "Concurrency invariant #{rows}" unless rows.map { |row| row["http"] }.sort == expected
      after = JSON.parse(call.call("counts"))
      added = %w[create incompatible].include?(operation) || (operation == "archive_create" && rows[1]["http"] == 200) ? 1 : 0
      raise "Duplicate or partial effect #{before} #{after}" unless after["references"] == before["references"] + added && after["unique_uids"] == after["references"] && after["parent_version"] == before["parent_version"] + 1
      results[operation] = { responses: rows, before: before, after: after }
    ensure
      remaining.each { |pid| Process.kill("KILL", pid) rescue Errno::ESRCH; Process.wait(pid) rescue Errno::ECHILD }
    end
  end
  call.call("reset")
  results[:integrity] = JSON.parse(call.call("snapshot"))
  results[:reopen] = JSON.parse(call.call("reopen"))
  workers = %w[busy_http holder].to_h do |mode|
    log = File.open(File.join(directory, "#{mode}.log"), "w")
    pid = Process.spawn(env.merge("D3_MODE" => mode), "bin/rails", "runner", runner, chdir: root, out: log, err: log)
    log.close; [ mode, pid ]
  end
  remaining = workers.values.dup
  begin
    _, status = Timeout.timeout(35) { Process.wait2(workers["busy_http"]) }; remaining.delete(workers["busy_http"])
    output = File.read(File.join(directory, "busy_http.log")); raise output unless status.success?
    results[:contention] = JSON.parse(output)
    File.write(File.join(directory, "writer-release"), "release")
    _, status = Timeout.timeout(35) { Process.wait2(workers["holder"]) }; remaining.delete(workers["holder"])
    raise "Holder failed" unless status.success?
    results[:rollback_reopen] = JSON.parse(call.call("reopen"))
  ensure
    remaining.each { |pid| Process.kill("KILL", pid) rescue Errno::ESRCH; Process.wait(pid) rescue Errno::ECHILD }
  end
end
File.write(File.join(evidence, "reference-process-results.json"), JSON.pretty_generate(results) + "\n")
puts JSON.pretty_generate(results)
