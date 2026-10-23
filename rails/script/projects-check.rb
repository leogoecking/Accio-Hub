#!/usr/bin/env ruby
require "bundler/setup"
require "tmpdir"
require "open3"
require "json"
require "fileutils"
require "timeout"

root = File.expand_path("..", __dir__)
evidence = ENV.fetch("ACCIO_QA_EVIDENCE", File.expand_path("../../docs/assets/p1.2d1", __dir__))
FileUtils.mkdir_p(evidence)
results = {}
Dir.mktmpdir("p12d-contract-", File.join(root, "tmp")) do |directory|
  env = { "RAILS_ENV" => "test", "ACCIO_DATABASE_PATH" => File.join(directory, "synthetic.sqlite3"), "P12D_WORKSPACE" => directory }
  runner = File.join(directory, "runner.rb")
  File.write(runner, <<~'RUBY')
    require "json"
    require "timeout"
    directory = ENV.fetch("P12D_WORKSPACE")
    raise "Expected synthetic isolated database" unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database.start_with?(directory + "/")
    mode = ENV.fetch("P12D_MODE")
    if mode == "seed"
      password = SecureRandom.hex(20)
      User.create!(email_address: "preferences@example.test", password: password)
      File.write(File.join(directory, "credential.json"), JSON.generate({ password: password }), mode: "w", perm: 0o600)
      AppearancePreferences.new(User.first).bootstrap(legacy: nil, raw: nil)
      File.write(File.join(directory, "intent"), ProjectCommands.new(User.first).issue)
      exit
    end
    store = AppearancePreferences.new(User.first)
    if mode == "worker"
      index = ENV.fetch("P12D_WORKER")
      operation = ENV.fetch("P12D_OPERATION")
      require "action_dispatch/testing/integration"
      client = ActionDispatch::Integration::Session.new(Rails.application)
      client.host! "localhost"
      client.post "/session", params: { email_address: User.first.email_address, password: JSON.parse(File.read(File.join(directory, "credential.json"))).fetch("password") }, headers: { "REMOTE_ADDR" => "127.0.0.1" }
      commands = ProjectCommands.new(User.first)
      project = User.first.projects.first
      version = project&.lock_version
      intent = operation == "name" ? commands.issue : File.read(File.join(directory, "intent"))
      File.write(File.join(directory, "ready-#{index}"), "ready")
      Timeout.timeout(20) { sleep 0.01 until File.exist?(File.join(directory, "release")) }
      begin
        attributes = { name: operation == "incompatible" ? "Race #{index}" : "Race QA", description: "Sintético", icon: "grid", color: "#79dec0" }
        attributes[:name] = index == "0" ? "Nome concorrente QA" : "  NOME  CONCORRENTE QA  " if operation == "name"
        if operation == "edit"
          client.patch "/projects/#{project.to_param}", params: { version: version, project: {name: "Edição #{index}"} }, as: :json, headers: { "REMOTE_ADDR" => "127.0.0.1" }
        else
          client.post "/projects", params: { intent: intent, project: attributes }, as: :json, headers: { "REMOTE_ADDR" => "127.0.0.1" }
        end
        raise "Unexpected HTTP #{client.response.status}" unless [200,409,422].include?(client.response.status)
        puts JSON.generate({ worker: index, result: client.response.status == 200 ? "committed" : client.response.status == 422 ? "validation_rejected" : "conflict_rejected", http: client.response.status })
      rescue ProjectCommands::Conflict
        puts JSON.generate({ worker: index, result: "conflict_rejected" })
      end
    elsif mode == "next_intent"
      File.write(File.join(directory, "intent"), ProjectCommands.new(User.first).issue)
    elsif mode == "snapshot"
      state = store.read
      raise "Wrong counts" unless [UserPreference.count, DockShortcut.count, WidgetPlacement.count] == [1,8,7]
      raise "Race duplicated project" unless Project.count == 3
      raise "Out of scope writes" unless [Task, ProjectReference, FocusSession, FocusCommand].all? { |m| m.count.zero? }
      state = { preferences: state, projects: Project.order(:id).map(&:attributes) }
      connection = ActiveRecord::Base.connection
      raise "Triggers missing" unless connection.select_value("SELECT count(*) FROM sqlite_master WHERE type='trigger' AND name LIKE 'accio_%'") == 25
      raise "Foreign key violations" unless connection.select_all("PRAGMA foreign_key_check").rows.empty?
      File.write(File.join(directory, "snapshot.json"), JSON.generate(state.as_json))
      puts JSON.generate({ aggregate_version: state[:preferences][:version], preference_count: 1, dock_count: 8, widget_count: 7, triggers: 25, foreign_keys_intact: true, project_count: Project.count, other_modules_empty: true })
    elsif mode == "reopen"
      raise "Persistence lost" unless JSON.parse(File.read(File.join(directory, "snapshot.json"))) == { preferences: store.read, projects: Project.order(:id).map(&:attributes) }.as_json
      puts JSON.generate({ reopened_aggregate_identical: true })
    elsif mode == "busy_http"
      require "action_dispatch/testing/integration"
      client = ActionDispatch::Integration::Session.new(Rails.application)
      client.host! "localhost"
      client.post "/session", params: { email_address: User.first.email_address, password: JSON.parse(File.read(File.join(directory,"credential.json"))).fetch("password") }, headers: { "REMOTE_ADDR" => "127.0.0.1" }
      state = store.read
      project = User.first.projects.first
      # Short busy timeout only in this synthetic connection, never production config.
      ActiveRecord::Base.connection.raw_connection.busy_timeout(50)
      File.write(File.join(directory,"http-ready"), "ready")
      Timeout.timeout(20) { sleep 0.01 until File.exist?(File.join(directory,"writer-ready")) }
      client.patch "/projects/#{project.to_param}/command", params: {operation: "favorite", favorite: true, version: project.lock_version}, as: :json, headers: { "REMOTE_ADDR" => "127.0.0.1" }
      raise "Busy HTTP not handled" unless client.response.status == 503 && client.response.parsed_body["error"] == "database_busy"
      puts JSON.generate({ sqlite_writer_contention_http: 503, local_edit_retry_supported: true })
    elsif mode == "holder"
      Timeout.timeout(20) { sleep 0.01 until File.exist?(File.join(directory,"http-ready")) }
      ActiveRecord::Base.connection.execute("BEGIN IMMEDIATE")
      File.write(File.join(directory,"writer-ready"), "ready")
      Timeout.timeout(20) { sleep 0.01 until File.exist?(File.join(directory,"writer-release")) }
      ActiveRecord::Base.connection.execute("ROLLBACK")
    end
  RUBY
  run = lambda do |args, overrides = {}|
    output, errors, status = Open3.capture3(env.merge(overrides), *args, chdir: root)
    raise "Synthetic check failed: #{args.join(' ')}: #{errors} #{output[-3000..]}" unless status.success?
    output
  end
  call = ->(mode) { run.call([ "bin/rails", "runner", runner ], "P12D_MODE" => mode) }
  run.call([ "bin/rails", "db:schema:load" ])
  tests = run.call([ "bin/rails", "test" ])
  File.write(File.join(evidence, "rails-tests.log"), tests.rstrip + "\n")
  results[:rails_suite] = tests.lines.find { |line| line.match?(/\d+ runs, \d+ assertions/) }&.strip
  call.call("seed")
  %w[create incompatible name edit].each do |operation|
    call.call("next_intent") if operation == "incompatible"
    %w[ready-0 ready-1 release].each { |name| FileUtils.rm_f(File.join(directory, name)) }
    workers = 2.times.map do |index|
      log = File.open(File.join(directory, "worker-#{index}.log"), "w")
      pid = Process.spawn(env.merge("P12D_MODE" => "worker", "P12D_OPERATION" => operation, "P12D_WORKER" => index.to_s), "bin/rails", "runner", runner, chdir: root, out: log, err: log)
      log.close
      pid
    end
    remaining = workers.dup
    begin
      Timeout.timeout(30) { sleep 0.01 until 2.times.all? { |i| File.exist?(File.join(directory, "ready-#{i}")) } }
      File.write(File.join(directory, "release"), "release")
      rows = workers.each_with_index.map do |pid, index|
        _, status = Timeout.timeout(30) { Process.wait2(pid) }
        remaining.delete(pid)
        output = File.read(File.join(directory, "worker-#{index}.log"))
        raise "Worker failed: #{output[0, 5000]}" unless status.success?
        JSON.parse(output)
      end
      raise "Overwrite between processes" unless rows.map { |row| row.fetch("result") }.sort == (operation == "create" ? %w[committed committed] : operation == "name" ? %w[committed validation_rejected] : %w[committed conflict_rejected])
      results[operation] = rows
    ensure
      remaining.each { |pid| Process.kill("KILL", pid) rescue Errno::ESRCH; Process.wait(pid) rescue Errno::ECHILD }
    end
  end
  results[:snapshot] = JSON.parse(call.call("snapshot"))
  results[:reopen] = JSON.parse(call.call("reopen"))
  processes = %w[busy_http holder].to_h do |mode|
    log = File.open(File.join(directory, "#{mode}.log"), "w")
    pid = Process.spawn(env.merge("P12D_MODE" => mode), "bin/rails", "runner", runner, chdir: root, out: log, err: log)
    log.close
    [ mode, pid ]
  end
  remaining = processes.values.dup
  begin
    _, status = Timeout.timeout(30) { Process.wait2(processes.fetch("busy_http")) }
    remaining.delete(processes.fetch("busy_http"))
    output = File.read(File.join(directory, "busy_http.log"))
    raise "Contention test failed: #{output[-2000..]}" unless status.success?
    results[:contention] = JSON.parse(output)
    File.write(File.join(directory, "writer-release"), "release")
    _, holder_status = Timeout.timeout(30) { Process.wait2(processes.fetch("holder")) }
    remaining.delete(processes.fetch("holder"))
    raise "Writer failed" unless holder_status.success?
    results[:post_contention] = JSON.parse(call.call("reopen"))
  ensure
    remaining.each { |pid| Process.kill("KILL", pid) rescue Errno::ESRCH; Process.wait(pid) rescue Errno::ECHILD }
  end
end
File.write(File.join(evidence, "project-process-results.json"), JSON.pretty_generate(results) + "\n")
puts JSON.pretty_generate(results)
