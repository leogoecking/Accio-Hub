#!/usr/bin/env ruby
require "bundler/setup"
require "tmpdir"
require "open3"
require "json"
require "fileutils"
require "timeout"

root = File.expand_path("..", __dir__)
evidence = ENV.fetch("ACCIO_QA_EVIDENCE", File.expand_path("../../docs/assets/p1.2e1", __dir__))
FileUtils.mkdir_p(evidence)
results = {}
Dir.mktmpdir("p12e1-contract-", File.join(root, "tmp")) do |directory|
  env = { "RAILS_ENV" => "test", "ACCIO_DATABASE_PATH" => File.join(directory, "synthetic.sqlite3"), "E1_WORKSPACE" => directory }
  runner = File.join(directory, "runner.rb")
  File.write(runner, <<~'CODE')
    require "json"
    require "timeout"
    directory = ENV.fetch("E1_WORKSPACE")
    raise "Synthetic only" unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database.start_with?(directory + "/")
    mode = ENV.fetch("E1_MODE")
    operation = ENV["E1_OPERATION"]
    user = User.first
    engine = FocusCommands.new(user) if user
    if mode == "initialize"
      password = SecureRandom.hex(24)
      user = User.create!(email_address: "focus@example.test", password: password)
      AppearancePreferences.new(user).bootstrap(legacy: nil, raw: nil)
      user.projects.create!(uid: "42/á?%#项目", name: "Sintético")
      File.write(File.join(directory, "credential.json"), JSON.generate({ password: password }), mode: "w", perm: 0o600)
      exit
    end
    def domain_snapshot(user)
      [ FocusSession.order(:id).map(&:attributes), FocusCommand.order(:id).map(&:attributes),
        UserPreference.order(:id).map(&:attributes), Project.order(:id).map(&:attributes), Task.order(:id).map(&:attributes) ].as_json
    end
    if mode == "seed"
      occupied = user.focus_sessions.occupying.first
      engine.command(uid: occupied.uid, command_id: SecureRandom.uuid, version: occupied.lock_version, kind: "reset", parameters: { "action" => "cancel" }) if occupied
      project = user.projects.first
      project.restore! if project.status == "archived"
      data = { "intent" => engine.issue, "other_intent" => engine.issue }
      case operation
      when "confirm", "reset_complete"
        session = user.focus_sessions.create!(status: "awaiting_confirmation", started_at: Time.current - 1500, elapsed_seconds: 1500)
      when "pause_resume", "archive_resume"
        session = user.focus_sessions.create!(status: "paused", started_at: Time.current, paused_at: Time.current,
          project: operation == "archive_resume" ? project : nil)
      when "archive_start"
        session = user.focus_sessions.create!(project: project)
      when "resolve"
        require Rails.root.join("test/support/focus_helpers")
        clock = FocusTestClock.new
        timed = FocusCommands.new(user, time: FocusTime.new(clock: clock, observations: FocusTime::Observations.new))
        timed.prepare(intent: timed.issue, command_id: SecureRandom.uuid, version: 0, action: "start_new")
        session = user.focus_sessions.occupying.first
        clock.advance(75)
        timed.command(uid: session.uid, command_id: SecureRandom.uuid, version: session.lock_version, kind: "pause", parameters: { "action" => "reconcile" })
        data["recovery"] = timed.read.fetch("recovery")
        session.reload
      when "busy", "replay"
        data["command_id"] = SecureRandom.uuid
        data["original"] = engine.prepare(intent: data.fetch("intent"), command_id: data.fetch("command_id"), version: 0, action: "start_new").fetch("result")
        session = user.focus_sessions.occupying.first
        engine.command(uid: session.uid, command_id: SecureRandom.uuid, version: session.lock_version, kind: "pause", parameters: { "action" => "pause" }) if operation == "replay"
        session.reload
      end
      data.merge!("uid" => session.to_param, "version" => session.lock_version) if session
      data.merge!("project" => project.to_param, "project_version" => project.lock_version)
      File.write(File.join(directory, "case.json"), JSON.generate(data))
      File.write(File.join(directory, "snapshot.json"), JSON.generate(domain_snapshot(user)))
      exit
    end
    data = JSON.parse(File.read(File.join(directory, "case.json")))
    if mode == "worker" || mode == "busy_http"
      require "action_dispatch/testing/integration"
      client = ActionDispatch::Integration::Session.new(Rails.application)
      client.host! "localhost"
      headers = { "REMOTE_ADDR" => "127.0.0.1" }
      client.post "/session", params: { email_address: user.email_address, password: JSON.parse(File.read(File.join(directory, "credential.json"))).fetch("password") }, headers: headers
      raise "Authentication failed" unless client.response.redirect?
      index = ENV.fetch("E1_WORKER", "0")
      if mode == "busy_http"
        FocusSession.connection.execute("PRAGMA busy_timeout=50")
        File.write(File.join(directory, "busy-ready"), "ready")
        Timeout.timeout(30) { sleep 0.01 until File.exist?(File.join(directory, "held")) }
        client.post "/focus/#{data.fetch('uid')}/commands", params: { command_id: "busy", version: data.fetch("version"), kind: "reset", parameters: { action: "cancel" } }, as: :json, headers: headers
        raise "Expected recoverable 503" unless client.response.status == 503
        puts JSON.generate({ http: 503, recoverable: client.response.parsed_body["error"] == "database_busy" })
      else
      File.write(File.join(directory, "ready-#{index}"), "ready")
      Timeout.timeout(30) { sleep 0.01 until File.exist?(File.join(directory, "release")) }
      case operation
      when "start", "same_intent"
        token = operation == "same_intent" || index == "0" ? data.fetch("intent") : data.fetch("other_intent")
        key = operation == "same_intent" ? "same-command" : "start-#{index}"
        client.post "/focus/prepare", params: { intent: token, command_id: key, version: 0, operation: "start_new" }, as: :json, headers: headers
      when "confirm", "reset_complete", "pause_resume", "resolve"
        action = case operation
        when "confirm" then "confirm"
        when "reset_complete" then index == "0" ? "restart" : "confirm"
        when "pause_resume" then index == "0" ? "pause" : "resume"
        else "resolve"
        end
        kind = { "confirm" => "complete", "restart" => "reset", "pause" => "pause", "resume" => "start", "resolve" => "pause" }.fetch(action)
        parameters = { action: action }
        parameters[:intent] = data.fetch("intent") if action == "restart"
        parameters.merge!(recovery_id: data.fetch("recovery").fetch("receipt_id"), decision: index == "0" ? "keep_checkpoint" : "accept_estimate") if action == "resolve"
        client.post "/focus/#{data.fetch('uid')}/commands", params: { command_id: "#{operation}-#{index}", version: data.fetch("version"), kind: kind, parameters: parameters }, as: :json, headers: headers
      when "archive_start", "archive_resume"
        if index == "0"
          client.patch "/projects/#{data.fetch('project')}/command", params: { version: data.fetch("project_version"), operation: "archive" }, as: :json, headers: headers
        else
          action = operation == "archive_start" ? "start" : "resume"
          client.post "/focus/#{data.fetch('uid')}/commands", params: { command_id: operation, version: data.fetch("version"), kind: "start", parameters: { action: action } }, as: :json, headers: headers
        end
      end
      raise "Unexpected #{client.response.status}: #{client.response.body}" unless [ 200, 409 ].include?(client.response.status)
      puts JSON.generate({ worker: index, http: client.response.status, replayed: client.response.parsed_body["replayed"] })
      end
    elsif mode == "holder"
      Timeout.timeout(30) { sleep 0.01 until File.exist?(File.join(directory, "busy-ready")) }
      FocusSession.connection.execute("BEGIN IMMEDIATE")
      File.write(File.join(directory, "held"), "held")
      Timeout.timeout(30) { sleep 0.01 until File.exist?(File.join(directory, "writer-release")) }
      FocusSession.connection.execute("ROLLBACK")
    elsif mode == "verify"
      before = JSON.parse(File.read(File.join(directory, "snapshot.json")))
      after = domain_snapshot(user)
      occupying = user.focus_sessions.occupying.count
      raise "Duplicate slot" unless occupying <= 1
      added = after[1].size - before[1].size
      if operation.start_with?("archive_")
        raise "Archive missing" unless user.projects.first.status == "archived"
        raise "Context altered" unless user.focus_sessions.order(:id).last.project_id == user.projects.first.id
        raise "Unexpected focus effects" unless [ 0, 1 ].include?(added)
      else
        raise "Effect not exactly once" unless added == 1
      end
      raise "FK violation" unless FocusSession.connection.select_all("PRAGMA foreign_key_check").empty?
      puts JSON.generate({ occupying: occupying, receipts_added: added, sessions_added: after[0].size - before[0].size,
        completed: user.focus_sessions.where(status: "completed").count, archived: user.projects.first.status == "archived" })
    elsif mode == "reopen"
      raise "Reopen mismatch" unless domain_snapshot(user) == JSON.parse(File.read(File.join(directory, "snapshot.json")))
      if operation == "resolve"
        raise "Recovery disappeared" unless engine.read.fetch("recovery") == data.fetch("recovery")
      end
      puts JSON.generate({ identical: true, recovery_preserved: operation == "resolve" })
    elsif mode == "replay"
      before = domain_snapshot(user)
      reply = engine.prepare(intent: data.fetch("intent"), command_id: data.fetch("command_id"), version: 0, action: "start_new")
      raise "Replay history changed" unless reply.fetch("result") == data.fetch("original") && reply.fetch("replayed")
      raise "Current went backward" unless reply.dig("current", "session", "status") == "paused"
      raise "Replay wrote data" unless before == domain_snapshot(user)
      puts JSON.generate({ replay_after_restart: true, historical_running: true, current_paused: true, no_writes: true })
    elsif mode == "integrity"
      connection = FocusSession.connection
      trigger_sql = connection.select_values("SELECT sql FROM sqlite_master WHERE type='trigger' ORDER BY name")
      expected = JSON.parse(File.read(File.join(directory, "triggers.json")))
      raise "Triggers changed" unless trigger_sql == expected && trigger_sql.size == 25
      raise "FK violation" unless connection.select_all("PRAGMA foreign_key_check").empty?
      puts JSON.generate({ triggers_identical: 25, foreign_keys: true, wal: connection.select_value("PRAGMA journal_mode"), synchronous: connection.select_value("PRAGMA synchronous") })
    end
  CODE
  RubyVM::InstructionSequence.compile(File.read(runner))
  run = ->(command, extra = {}) do
    output, errors, status = Open3.capture3(env.merge(extra), *command, chdir: root)
    raise "Synthetic check failed: #{command.join(' ')}\n#{output}\n#{errors}" unless status.success?
    output
  end
  call = ->(mode, operation = nil) { run.call([ "bin/rails", "runner", runner ], { "E1_MODE" => mode, "E1_OPERATION" => operation }.compact) }
  run.call([ "bin/rails", "db:schema:load" ])
  tests = run.call([ "bin/rails", "test" ])
  File.write(File.join(evidence, "rails-tests.log"), tests)
  results[:suite] = tests.lines.find { |line| line.include?(" runs, ") }&.strip
  File.write(File.join(evidence, "zeitwerk.log"), run.call([ "bin/rails", "zeitwerk:check" ]))
  trigger_code = "require 'json'; File.write(File.join(ENV.fetch('E1_WORKSPACE'),'triggers.json'), JSON.generate(FocusSession.connection.select_values(\"SELECT sql FROM sqlite_master WHERE type='trigger' ORDER BY name\")))"
  run.call([ "bin/rails", "runner", trigger_code ])
  call.call("initialize")
  %w[start same_intent confirm pause_resume reset_complete resolve archive_start archive_resume].each do |operation|
    call.call("seed", operation)
    results[:recovery_restart] = JSON.parse(call.call("reopen", operation)) if operation == "resolve"
    %w[ready-0 ready-1 release].each { |name| FileUtils.rm_f(File.join(directory, name)) }
    workers = 2.times.map do |index|
      log = File.open(File.join(directory, "worker-#{index}.log"), "w")
      pid = Process.spawn(env.merge("E1_MODE" => "worker", "E1_OPERATION" => operation, "E1_WORKER" => index.to_s), "bin/rails", "runner", runner, chdir: root, out: log, err: log)
      log.close; pid
    end
    remaining = workers.dup
    begin
      Timeout.timeout(40) { sleep 0.01 until 2.times.all? { |i| File.exist?(File.join(directory, "ready-#{i}")) } }
      File.write(File.join(directory, "release"), "go")
      rows = workers.each_with_index.map do |pid, index|
        _, status = Timeout.timeout(40) { Process.wait2(pid) }; remaining.delete(pid)
        output = File.read(File.join(directory, "worker-#{index}.log"))
        raise output unless status.success?
        JSON.parse(output)
      end
      expected = operation == "same_intent" ? [ 200, 200 ] : operation.start_with?("archive_") ? nil : [ 200, 409 ]
      raise "Unexpected race #{rows}" if expected && rows.map { |r| r.fetch("http") }.sort != expected
      state = JSON.parse(call.call("verify", operation))
      if operation.start_with?("archive_")
        raise "Archive/focus ordering mismatch" unless rows[0].fetch("http") == 200 && state.fetch("receipts_added") == (rows[1].fetch("http") == 200 ? 1 : 0)
      end
      results[operation] = { responses: rows, state: state }
      puts "PASS #{operation}"
    ensure
      remaining.each { |pid| Process.kill("KILL", pid) rescue Errno::ESRCH; Process.wait(pid) rescue Errno::ECHILD }
    end
  end
  call.call("seed", "replay")
  results[:replay_restart] = JSON.parse(call.call("replay"))
  call.call("seed", "busy")
  %w[busy-ready held writer-release].each { |name| FileUtils.rm_f(File.join(directory, name)) }
  workers = %w[busy_http holder].to_h do |mode|
    log = File.open(File.join(directory, "#{mode}.log"), "w")
    pid = Process.spawn(env.merge("E1_MODE" => mode), "bin/rails", "runner", runner, chdir: root, out: log, err: log)
    log.close; [ mode, pid ]
  end
  remaining = workers.values.dup
  begin
    _, status = Timeout.timeout(40) { Process.wait2(workers.fetch("busy_http")) }; remaining.delete(workers.fetch("busy_http"))
    output = File.read(File.join(directory, "busy_http.log")); raise output unless status.success?
    results[:contention] = JSON.parse(output)
    File.write(File.join(directory, "writer-release"), "release")
    _, status = Timeout.timeout(40) { Process.wait2(workers.fetch("holder")) }; remaining.delete(workers.fetch("holder"))
    raise "Holder failed" unless status.success?
    results[:contention_rollback] = JSON.parse(call.call("reopen"))
  ensure
    remaining.each { |pid| Process.kill("KILL", pid) rescue Errno::ESRCH; Process.wait(pid) rescue Errno::ECHILD }
  end
  results[:integrity] = JSON.parse(call.call("integrity"))
end
File.write(File.join(evidence, "process-results.json"), JSON.pretty_generate(results) + "\n")
puts JSON.pretty_generate(results)
