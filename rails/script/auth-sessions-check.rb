#!/usr/bin/env ruby
require "bundler/setup"
require "tmpdir"
require "open3"
require "fileutils"
require "timeout"
require "securerandom"
require_relative "../app/services/synthetic_auth_session_cleanup"
require_relative "../app/services/synthetic_sqlite_backup"

root = File.expand_path("..", __dir__)
evidence = File.expand_path(ENV.fetch("ACCIO_QA_EVIDENCE"))
FileUtils.mkdir_p(evidence)
results = {}
Dir.mktmpdir("accio-f3c-process-") do |directory|
  database = File.join(directory, "synthetic.sqlite3")
  fixture = File.join(directory, "fixture.json")
  File.write(fixture, JSON.generate({ format: "accio-f3a-synthetic", version: 1, database: "synthetic.sqlite3" }), perm: 0o600)
  reference = Time.now.utc.floor(6)
  env = { "RAILS_ENV" => "test", "ACCIO_DATABASE_PATH" => database, "ACCIO_SYNTHETIC_FIXTURE" => fixture,
    "SECRET_KEY_BASE" => SecureRandom.hex(64), "SECRET_KEY_BASE_DUMMY" => nil,
    "F3C_REFERENCE_TIME" => reference.iso8601(6), "ACCIO_SESSION_CLEANUP_CONFIRM" => nil }
  run = lambda do |args, changes = {}|
    output, error, status = Open3.capture3(env.merge(changes), *args, chdir: root)
    raise "Synthetic command failed: #{args.first(2).join(' ')} #{error.lines.first}" unless status.success?
    output
  end
  run.call([ "bin/rails", "db:schema:load" ])
  File.chmod(0o600, database)
  # Reuse the unchanged full-domain synthetic seed, not operational data.
  run.call([ "bin/rails", "runner", "script/sqlite-backups-worker.rb" ], "F3B_WORKSPACE" => directory, "F3B_MODE" => "seed")
  db = SQLite3::Database.new(database)
  db.execute("PRAGMA foreign_keys=ON")
  db.execute("PRAGMA journal_mode=WAL")
  db.execute("PRAGMA synchronous=FULL")
  records = lambda do
    db.execute("BEGIN")
    tables = db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").flatten
    tables.to_h do |table|
      columns = db.execute("PRAGMA table_info(#{SqliteBackupSnapshot.quote(table)})").size
      [ table, db.execute("SELECT * FROM #{SqliteBackupSnapshot.quote(table)} ORDER BY #{(1..columns).to_a.join(',')}") ]
    end
  ensure
    db.execute("ROLLBACK")
  end
  initial_schema = SqliteBackupSnapshot.schema(db)
  original = records.call
  inventory = JSON.parse(run.call([ "bin/rails", "admin:sessions:inventory" ]))
  dry = JSON.parse(run.call([ "bin/rails", "admin:sessions:cleanup" ]))
  raise "Dry run wrote data" unless records.call == original && !inventory["committed"] && !dry["committed"] && dry["deleted"].zero?
  results[:cli_dry_runs_read_only] = true
  out, err, status = Open3.capture3(env.merge("ACCIO_SESSION_CLEANUP_CONFIRM" => "invalid"), "bin/rails", "admin:sessions:cleanup", chdir: root)
  raise "Invalid confirmation accepted or leaked data" if status.success? || !out.empty? || !err.include?("Operação recusada") || records.call != original
  missing = File.join(directory, "must-not-create.sqlite3")
  [ { "RAILS_ENV" => "development" }, { "ACCIO_DATABASE_PATH" => nil }, { "ACCIO_DATABASE_PATH" => missing }, { "ACCIO_SYNTHETIC_FIXTURE" => nil } ].each do |changes|
    out, err, status = Open3.capture3(env.merge(changes), "bin/rails", "admin:sessions:cleanup", chdir: root)
    raise "Unsafe guard accepted" if status.success? || !out.empty? || !err.include?("Operação recusada") || File.exist?(missing)
  end
  results[:unsafe_cli_and_confirmation_refused] = true
  active_rows = db.execute("SELECT * FROM auth_sessions WHERE expires_at > ? ORDER BY id", [ reference.strftime("%Y-%m-%d %H:%M:%S.%6N") ])
  cleaned = JSON.parse(run.call([ "bin/rails", "admin:sessions:cleanup" ], "ACCIO_SESSION_CLEANUP_CONFIRM" => SyntheticAuthSessionCleanup::CONFIRMATION))
  current = records.call
  raise "Ordinary cleanup changed unrelated records" unless cleaned["deleted"] == 1 && original.except("auth_sessions") == current.except("auth_sessions") && current["auth_sessions"] == active_rows
  raise "Restart repeated deletion" unless JSON.parse(run.call([ "bin/rails", "admin:sessions:cleanup" ], "ACCIO_SESSION_CLEANUP_CONFIRM" => SyntheticAuthSessionCleanup::CONFIRMATION))["deleted"].zero?
  results[:full_domain_preserved] = { tables: original.keys.size, only_expired_deleted: true, active_rows_byte_equal: true, repeat_after_new_process: true }
  worker = [ RbConfig.ruby, File.join(root, "script/auth-sessions-worker.rb") ]
  children = []
  start = lambda do |changes|
    input, output, error, waiter = Open3.popen3(env.merge(changes), *worker, chdir: root)
    child = [ input, output, error, waiter ]
    children << child
    child
  end
  line = ->(child) { JSON.parse(Timeout.timeout(20) { child[1].gets } || raise("Missing synthetic child result")) }
  held = ->(child) { raise "Expected real lock barrier" unless line.call(child) == { "event" => "held" } }
  release = lambda do |child, exit_code = 0|
    child[0].puts("release")
    child[0].close
    result = line.call(child)
    raise "Unexpected process result" unless child[3].value.exitstatus == exit_code
    result
  end
  add = lambda do |time|
    raw = time.strftime("%Y-%m-%d %H:%M:%S.%6N")
    db.execute("INSERT INTO auth_sessions(user_id,expires_at,created_at,updated_at) VALUES(1,?,?,?)", [ raw, raw, raw ])
    db.last_insert_row_id
  end
  results[:process_races] = []
  add.call(reference - Rational(1, 1_000_000))
  add.call(reference)
  boundary_active = add.call(reference + Rational(1, 1_000_000))
  boundary = JSON.parse(run.call(worker, "F3C_MODE" => "cleanup"))
  raise "Fixed process cutoff lost valid boundary session" unless boundary["deleted"] == 2 && db.get_first_value("SELECT count(*) FROM auth_sessions WHERE id=?", [ boundary_active ]) == 1
  results[:subprocess_boundary] = { before_and_equal_deleted: 2, after_cutoff_preserved: true }
  %w[logout extend create].each do |operation|
    row = add.call(reference - 10)
    writer = start.call("F3C_MODE" => "writer", "F3C_WRITE" => operation, "F3C_ROW" => row.to_s)
    held.call(writer)
    cleaner = start.call("F3C_MODE" => "cleanup", "F3C_HOLD_STAGE" => "cutoff_fixed")
    held.call(cleaner)
    # Cleaner has already fixed cutoff, then observes the other process's commit.
    release.call(writer)
    release.call(cleaner)
    exists = db.get_first_value("SELECT count(*) FROM auth_sessions WHERE id=?", [ row ])
    raise "Concurrent extension lost" if operation == "extend" && exists != 1
    raise "Expired row survived" if operation != "extend" && exists != 0
    raise "New active session removed" if operation == "create" && db.get_first_value("SELECT count(*) FROM auth_sessions WHERE expires_at > ?", [ reference.strftime("%Y-%m-%d %H:%M:%S.%6N") ]) < 1
    results[:process_races] << { operation: operation, preserved: true }
  end
  add.call(reference - 10)
  first = start.call("F3C_MODE" => "cleanup", "F3C_HOLD_STAGE" => "before_commit")
  held.call(first)
  read_during = JSON.parse(run.call(worker, "F3C_MODE" => "inventory"))
  raise "Read-only inventory saw uncommitted deletion" unless read_during["expired"] == 1 && read_during["deleted"].zero?
  results[:wal_inventory_excludes_uncommitted_cleanup] = true
  second = start.call("F3C_MODE" => "cleanup", "F3C_HOLD_STAGE" => "cutoff_fixed")
  held.call(second)
  first_result = release.call(first)
  second_result = release.call(second)
  raise "Simultaneous deletion duplicated" unless first_result["deleted"] == 1 && second_result["deleted"].zero?
  results[:process_races] << { operation: "two_cleaners", deleted_once: true }
  add.call(reference - 10)
  before_failure = records.call
  failing = start.call("F3C_MODE" => "cleanup", "F3C_HOLD_STAGE" => "before_commit", "F3C_FAIL" => "1")
  held.call(failing)
  release.call(failing, 74)
  raise "Failed transaction left partial changes" unless records.call == before_failure
  results[:late_failure_full_rollback] = true
  lock = start.call("F3C_MODE" => "writer", "F3C_WRITE" => "lock")
  held.call(lock)
  busy = start.call("F3C_MODE" => "cleanup")
  busy_result = line.call(busy)
  raise "Real SQLite contention not handled" unless busy[3].value.exitstatus == 75 && busy_result == { "status" => "busy", "committed" => false }
  out, err, status = Open3.capture3(env.merge("ACCIO_SESSION_CLEANUP_CONFIRM" => SyntheticAuthSessionCleanup::CONFIRMATION), "bin/rails", "admin:sessions:cleanup", chdir: root)
  raise "CLI contention not controlled" if status.success? || !out.empty? || !err.include?("Contenção SQLite recuperável")
  release.call(lock)
  raise "Contention changed source" unless records.call == before_failure
  results[:real_sqlite_busy_rollback] = true
  results[:real_sqlite_busy_cli_controlled] = true
  # SIGKILL rolls back an uncommitted deletion; no system clocks or services touched.
  killed = start.call("F3C_MODE" => "cleanup", "F3C_HOLD_STAGE" => "before_commit")
  held.call(killed)
  Process.kill("KILL", killed[3].pid)
  killed[3].value
  raise "Killed transaction changed source" unless records.call == before_failure
  results[:sigkill_rollback] = true
  run.call(worker, "F3C_MODE" => "cleanup")
  raise "Schema changed" unless SqliteBackupSnapshot.schema(db) == initial_schema
  raise "Integrity failed" unless db.get_first_value("PRAGMA integrity_check") == "ok" && db.execute("PRAGMA foreign_key_check").empty?
  objects = initial_schema["objects"]
  results[:sqlite] = { triggers: objects.count { |r| r[0] == "trigger" }, indexes: objects.count { |r| r[0] == "index" },
    same_sql: true, foreign_keys: db.get_first_value("PRAGMA foreign_keys"), integrity: "ok", foreign_key_violations: [],
    journal_mode: db.get_first_value("PRAGMA journal_mode"), synchronous: db.get_first_value("PRAGMA synchronous") }
  raise "Wrong structure" unless results[:sqlite][:triggers] == 25 && results[:sqlite][:indexes] == 36
  backup = SyntheticSqliteBackup.new(fixture: fixture, database: database, environment: "test", checkout: File.dirname(root))
  archive = File.join(directory, "after-cleanup.tar")
  before_backup = records.call
  captured = backup.backup(destination: archive)
  raise "Backup regression" unless captured == backup.verify(archive) && records.call == before_backup
  results[:backup_after_ordinary_cleanup_verified_source_unchanged] = true
  # In-process HTTP dispatch using a real signed synthetic cookie and real password.
  probe = File.join(directory, "auth-check.rb")
  File.write(probe, <<~'RUBY', perm: 0o600)
    require "action_dispatch/testing/integration"
    state = JSON.parse(File.read(File.join(File.dirname(ENV.fetch("ACCIO_SYNTHETIC_FIXTURE")), "state.json")))
    client = ActionDispatch::Integration::Session.new(Rails.application)
    client.host! "localhost"
    client.get "/focus/state", headers: { "REMOTE_ADDR" => "127.0.0.1", "HTTP_ACCEPT" => "application/json", "Cookie" => state.fetch("old_cookie") }
    raise "Active cookie lost" unless client.response.status == 200
    password_before = User.find(1).password_digest
    client.post "/session", params: { email_address: User.find(1).email_address, password: state.fetch("password") }, headers: { "REMOTE_ADDR" => "127.0.0.1" }
    raise "Password login lost" unless client.response.status == 303
    expired_id = AuthSession.maximum(:id)
    AuthSession.find(expired_id).update!(expires_at: 1.minute.ago)
    client.get "/focus/state", headers: { "REMOTE_ADDR" => "127.0.0.1", "HTTP_ACCEPT" => "application/json" }
    raise "Expired cookie authenticated before maintenance" unless client.response.status == 401
    maintenance = SyntheticAuthSessionCleanup.new(fixture: ENV.fetch("ACCIO_SYNTHETIC_FIXTURE"), database: ENV.fetch("ACCIO_DATABASE_PATH"), environment: Rails.env.to_s, checkout: Rails.root.parent.to_s)
    raise "Expired session not removed" unless maintenance.cleanup(confirmation: SyntheticAuthSessionCleanup::CONFIRMATION)["deleted"] >= 1 && !AuthSession.exists?(expired_id)
    client.get "/focus/state", headers: { "REMOTE_ADDR" => "127.0.0.1", "HTTP_ACCEPT" => "application/json" }
    raise "Expired cookie authenticated after maintenance" unless client.response.status == 401
    client.post "/session", params: { email_address: User.find(1).email_address, password: state.fetch("password") }, headers: { "REMOTE_ADDR" => "127.0.0.1" }
    raise "Fresh login failed" unless client.response.status == 303
    client.delete "/session", headers: { "REMOTE_ADDR" => "127.0.0.1" }
    raise "Logout failed" unless client.response.status == 303
    client.get "/focus/state", headers: { "REMOTE_ADDR" => "127.0.0.1", "HTTP_ACCEPT" => "application/json" }
    raise "Revocation failed" unless client.response.status == 401 && User.find(1).password_digest == password_before
    puts JSON.generate({ active_signed_cookie_preserved: true, expired_cookie_rejected_before_and_after_cleanup: true,
      password_login: true, logout_revocation: true, password_digest_preserved: true })
  RUBY
  results[:authentication] = JSON.parse(run.call([ "bin/rails", "runner", probe ]))
  results[:scope] = { synthetic_only: true, private_artifacts_in_evidence: false, operational_recovery_tested: false }
ensure
  children&.each do |input, output, error, waiter|
    Process.kill("TERM", waiter.pid) if waiter.alive?
    waiter.value
    [ input, output, error ].each { |io| io.close unless io.closed? }
  end
  db&.close
end
File.write(File.join(evidence, "integration.json"), JSON.pretty_generate(results) + "\n")
puts JSON.pretty_generate(results)
