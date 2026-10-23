#!/usr/bin/env ruby
require "bundler/setup"
require "sqlite3"
require "tmpdir"
require "open3"
require "json"
require "digest"
require "benchmark"
require "fileutils"
require "timeout"

# Creates only new, private temporary databases. No personal database argument.
root = File.expand_path("..", __dir__)
evidence = File.expand_path("../../docs/assets/p1.2b", __dir__)
FileUtils.mkdir_p(evidence)
results = {}

Dir.mktmpdir("p12b-contract-", File.join(root, "tmp")) do |directory|
  env = { "RAILS_ENV" => "test", "ACCIO_DATABASE_PATH" => File.join(directory, "migration.sqlite3"), "P12B_WORKSPACE" => directory }
  runner = File.join(directory, "runner.rb")
  source = <<~'RUBY'
    require "json"
    require "digest"
    require "timeout"
    directory = ENV.fetch("P12B_WORKSPACE")
    raise "Expected isolated synthetic database" unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database.start_with?(directory + "/")
    snapshot = File.join(directory, "snapshot.json")
    models = [ Project, Task, ProjectReference, UserPreference, DockShortcut, WidgetPlacement, FocusSession, FocusCommand ]
    case ENV.fetch("P12B_MODE")
    when "seed_auth"
      user = User.create!(email_address: "process@example.test", password: SecureRandom.hex(16))
      user.auth_sessions.create!(expires_at: 1.hour.from_now)
      user.auth_sessions.create!(expires_at: 1.hour.ago)
      File.write(snapshot, JSON.generate({ "auth" => Digest::SHA256.hexdigest(user.attributes.to_json) }), mode: "w", perm: 0o600)
    when "verify_migration"
      before = JSON.parse(File.read(snapshot))
      raise "Auth record changed" unless before.fetch("auth") == Digest::SHA256.hexdigest(User.first.attributes.to_json)
      raise "Sessions changed" unless AuthSession.count == 2
      raise "Unexpected seeded domain data" unless models.all? { |model| model.count.zero? }
      puts JSON.generate({ auth_preserved: true, sessions_preserved: true, empty_domain_tables: true })
    when "seed_domain"
      user = User.first
      project = user.projects.create!(uid: "legacy / UID-1", name: "Projeto sintético")
      task = user.tasks.create!(uid: "42", project: project, title: "Persistida")
      user.project_references.create!(uid: "reference-1", project: project, title: "Livro", kind: "material")
      user.create_user_preference!(theme: "light", legacy_cookie_backup: { "theme" => "light" })
      %w[tasks focus projects].each_with_index { |key, i| user.dock_shortcuts.create!(module_key: key, position: i) }
      user.widget_placements.create!(widget_key: "tasks", position: 0, span: 5)
      session = user.focus_sessions.create!(project: project, task: task)
      receipt = FocusCommand.record!(user: user, command_id: "seed-command", kind: "reset", focus_session: session, expected_version: 0) do |record|
        record.update!(duration_seconds: 2700)
        { "duration" => 2700 }
      end
      File.write(snapshot, JSON.generate(models.to_h { |model| [ model.name, model.order(:id).map { |r| r.attributes.as_json } ] }), mode: "w", perm: 0o600)
    when "verify_reopen"
      expected = JSON.parse(File.read(snapshot))
      observed = models.to_h { |model| [ model.name, model.order(:id).map { |r| r.attributes.as_json } ] }
      raise "Persistence mismatch after process exit" unless expected == observed
      session = FocusSession.first
      receipt = FocusCommand.record!(user: User.first, command_id: "seed-command", kind: "reset", focus_session: session, expected_version: 0) { raise "Must replay after restart" }
      raise "Receipt mismatch" unless receipt.result == { "duration" => 2700 }
      connection = ActiveRecord::Base.connection
      puts JSON.generate({ records_preserved: true, replay_after_restart: true, foreign_keys: connection.select_value("PRAGMA foreign_keys"), journal_mode: connection.select_value("PRAGMA journal_mode"), synchronous: connection.select_value("PRAGMA synchronous"), triggers: connection.select_value("SELECT count(*) FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'accio_%'") })
    when "schema_info"
      connection = ActiveRecord::Base.connection
      raise "Foreign key violations" unless connection.select_all("PRAGMA foreign_key_check").rows.empty?
      puts JSON.generate({ triggers: connection.select_values("SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'accio_%' ORDER BY name"), indexes: connection.select_values("SELECT sql FROM sqlite_master WHERE type = 'index' AND sql IS NOT NULL ORDER BY name") })
    when "prepare_global_race"
      FocusSession.occupying.first.update!(status: "cancelled", ended_at: Time.current, end_reason: "reset")
    when "worker"
      index = ENV.fetch("P12B_WORKER")
      operation = ENV.fetch("P12B_OPERATION")
      target = operation == "version" ? Task.first : operation == "order" ? UserPreference.first : FocusSession.occupying.first
      expected = target&.lock_version
      File.write(File.join(directory, "ready-#{index}"), "ready")
      Timeout.timeout(20) { sleep 0.01 until File.exist?(File.join(directory, "release")) }
      outcome = { operation: operation, worker: index }
      begin
        case operation
        when "version"
          target.update!(title: "Escritor #{index}")
          outcome[:result] = "committed"
        when "order"
          keys = index == "0" ? %w[projects focus tasks] : %w[focus tasks projects]
          DockShortcut.reorder!(user: User.first, module_keys: keys, expected_version: expected)
          outcome[:result] = "committed"
        when "command"
          receipt = FocusCommand.record!(user: User.first, command_id: "concurrent-command", kind: "reset", focus_session: target, expected_version: expected) do |record|
            record.update!(duration_seconds: 1500)
            { "version" => record.lock_version }
          end
          outcome.merge!(result: "receipt", receipt_id: receipt.id)
        when "global"
          FocusSession.insert_all!([{ user_id: 1, uid: "race-focus-#{index}", created_at: Time.current, updated_at: Time.current }])
          outcome[:result] = "committed"
        end
      rescue ActiveRecord::StaleObjectError
        outcome[:result] = "stale_rejected"
      rescue ActiveRecord::RecordNotUnique
        outcome[:result] = "unique_rejected"
      end
      puts JSON.generate(outcome)
    when "verify_races"
      raise "Task version mismatch" unless Task.first.lock_version == 1
      raise "Preference version mismatch" unless UserPreference.first.lock_version == 1
      raise "Order collision" unless DockShortcut.order(:position).pluck(:position) == [0, 1, 2]
      receipt = FocusCommand.find_by!(command_id: "concurrent-command")
      raise "Duplicate receipt" unless FocusCommand.where(command_id: receipt.command_id).count == 1
      raise "Duplicate command effect" unless receipt.result == { "version" => 2 }
      raise "Duplicate global timer" unless FocusSession.occupying.count == 1
      puts JSON.generate({ stale_writes_rejected: true, order_preserved: true, receipt_and_effect_once: true, one_global_occupant: true })
    end
  RUBY
  File.write(runner, source)

  run = lambda do |args, overrides = {}|
    output, errors, status = Open3.capture3(env.merge(overrides), *args, chdir: root)
    raise "Synthetic check failed: #{args.join(' ')}\n#{errors}\n#{output[-2000..]}" unless status.success?
    output
  end
  call = ->(mode, overrides = {}) { run.call([ "bin/rails", "runner", runner ], overrides.merge("P12B_MODE" => mode)) }
  # migrate:up builds the actual P1.1 tables without auto-loading today's schema.
  run.call([ "bin/rails", "db:migrate:up", "VERSION=20261011010000" ])
  call.call("seed_auth")
  File.write(File.join(evidence, "migration-from-p11.log"), run.call([ "bin/rails", "db:migrate" ]).rstrip + "\n")
  results[:upgrade_from_p11] = JSON.parse(call.call("verify_migration"))
  migrated = JSON.parse(call.call("schema_info"))
  schema_env = { "ACCIO_DATABASE_PATH" => File.join(directory, "schema-load.sqlite3") }
  File.write(File.join(evidence, "schema-load.log"), run.call([ "bin/rails", "db:schema:load" ], schema_env).rstrip + "\n")
  loaded = JSON.parse(call.call("schema_info", schema_env))
  raise "Schema load omitted integrity rules" unless migrated == loaded
  results[:schema_load] = { identical_triggers_and_indexes: true, trigger_count: loaded.fetch("triggers").size }
  tests = run.call([ "bin/rails", "test" ], schema_env)
  File.write(File.join(evidence, "rails-tests.log"), tests.rstrip + "\n")
  results[:rails_suite] = tests.lines.find { |line| line.match?(/\d+ runs, \d+ assertions/) }&.strip
  call.call("seed_domain")
  results[:process_reopen] = JSON.parse(call.call("verify_reopen"))

  %w[version order command global].each do |operation|
    call.call("prepare_global_race") if operation == "global"
    %w[ready-0 ready-1 release].each { |name| FileUtils.rm_f(File.join(directory, name)) }
    processes = 2.times.map do |index|
      log = File.open(File.join(directory, "worker-#{index}.log"), "w")
      pid = Process.spawn(env.merge("P12B_MODE" => "worker", "P12B_WORKER" => index.to_s, "P12B_OPERATION" => operation), "bin/rails", "runner", runner, chdir: root, out: log, err: log)
      log.close
      pid
    end
    remaining = processes.dup
    begin
      Timeout.timeout(30) { sleep 0.01 until 2.times.all? { |i| File.exist?(File.join(directory, "ready-#{i}")) } }
      File.write(File.join(directory, "release"), "release")
      outcomes = processes.each_with_index.map do |pid, i|
        _, status = Timeout.timeout(30) { Process.wait2(pid) }
        remaining.delete(pid)
        output = File.read(File.join(directory, "worker-#{i}.log"))
        raise "Worker failed: #{output[-1000..]}" unless status.success?
        JSON.parse(output)
      end
      actual = outcomes.map { |row| row.fetch("result") }.sort
      expected = operation == "global" ? %w[committed unique_rejected] : operation == "command" ? %w[receipt receipt] : %w[committed stale_rejected]
      raise "Concurrent operation mismatch" unless actual == expected
      raise "Different receipt IDs" if operation == "command" && outcomes.map { |r| r.fetch("receipt_id") }.uniq.size != 1
      results[operation.to_sym] = outcomes
    ensure
      remaining.each do |pid|
        Process.kill("KILL", pid) rescue Errno::ESRCH
        Process.wait(pid) rescue Errno::ECHILD
      end
    end
  end
  results[:race_verification] = JSON.parse(call.call("verify_races"))

  results[:durability] = %w[NORMAL FULL].to_h do |mode|
    path = File.join(directory, "benchmark-#{mode}.sqlite3")
    database = SQLite3::Database.new(path)
    database.execute("PRAGMA journal_mode = WAL")
    database.execute("PRAGMA synchronous = #{mode}")
    database.execute("CREATE TABLE samples (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)")
    samples = 3.times.map do
      Benchmark.realtime do
        200.times { database.transaction { database.execute("INSERT INTO samples(payload) VALUES (?)", [ "synthetic" * 10 ]) } }
      end
    end
    pragma = database.get_first_value("PRAGMA synchronous")
    database.close
    reopened = SQLite3::Database.new(path)
    raise "Committed data lost on reopen" unless reopened.get_first_value("SELECT count(*) FROM samples") == 600
    reopened.close
    [ mode, { synchronous: pragma, transactions_per_round: 200, seconds: samples, median_seconds: samples.sort[1], committed_rows_after_reopen: 600 } ]
  end
end

File.write(File.join(evidence, "process-results.json"), JSON.pretty_generate(results) + "\n")
puts JSON.pretty_generate(results)
