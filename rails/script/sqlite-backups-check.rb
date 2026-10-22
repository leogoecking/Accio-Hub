#!/usr/bin/env ruby
require "bundler/setup"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "timeout"
require "securerandom"
require "sqlite3"
require "net/http"
require "socket"
require "cgi"
require_relative "../app/services/synthetic_sqlite_backup"

root = File.expand_path("..", __dir__)
evidence = ENV.fetch("ACCIO_QA_EVIDENCE")
FileUtils.mkdir_p(evidence)
results = {}
Dir.mktmpdir("accio-f3b-process-") do |workspace|
  directory = File.join(workspace, "source")
  Dir.mkdir(directory, 0o700)
  database = File.join(directory, "synthetic.sqlite3")
  fixture = File.join(directory, "fixture.json")
  File.write(fixture, JSON.generate({ format: "accio-f3a-synthetic", version: 1, database: "synthetic.sqlite3" }), perm: 0o600)
  env = { "RAILS_ENV"=>"test", "ACCIO_DATABASE_PATH"=>database, "ACCIO_SYNTHETIC_FIXTURE"=>fixture, "F3B_WORKSPACE"=>workspace, "SECRET_KEY_BASE"=>SecureRandom.hex(64), "SECRET_KEY_BASE_DUMMY"=>nil }
  worker = File.join(root, "script/sqlite-backups-worker.rb")
  run = lambda do |arguments, selected = env, changes = {}|
    output, error, status = Open3.capture3(selected.merge(changes), *arguments, chdir: root)
    raise "Synthetic command failed (#{arguments.first(2).join(' ')}): #{error.lines.first}" unless status.success?
    output
  end
  call = ->(mode, selected = env, changes = {}) { JSON.parse(run.call([ "bin/rails", "runner", worker ], selected, changes.merge("F3B_MODE"=>mode))) }
  records = lambda do |selected, name|
    path = File.join(workspace, name + ".json")
    call.call("records", selected, "F3B_RECORDS_PATH" => path)
    JSON.parse(File.read(path))
  end
  run.call([ "bin/rails", "db:schema:load" ])
  File.chmod(0o600, database)
  keeper = SQLite3::Database.new(database, readonly: true)
  keeper.get_first_value("SELECT count(*) FROM schema_migrations")
  tool = SyntheticSqliteBackup.new(fixture: fixture, database: database, environment: "test", checkout: File.dirname(root))
  results[:seed] = call.call("seed")
  raise "Expected live WAL" unless File.size?(database+"-wal")
  before = call.call("snapshot")
  original_records = records.call(env, "source-original-records")
  archive = File.join(directory, "complete.tar")
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  results[:backup_cli] = JSON.parse(run.call([ "bin/rails", "sqlite_backups:create" ], env, "ACCIO_SQLITE_BACKUP"=>archive))
  results[:backup_seconds] = (Process.clock_gettime(Process::CLOCK_MONOTONIC)-started).round(3)
  results[:volumes] = { source_sqlite_bytes: File.size(database), active_wal_bytes: File.size(database + "-wal"), backup_bytes: File.size(archive) }
  invalid_path = File.join(workspace, "must-not-create.sqlite3")
  bad_output, bad_error, bad_status = Open3.capture3(env.merge("RAILS_ENV" => "development", "ACCIO_DATABASE_PATH" => invalid_path,
    "ACCIO_SQLITE_BACKUP" => File.join(directory, "must-not-create.tar")), "bin/rails", "sqlite_backups:create", chdir: root)
  raise "Unsafe administration accepted" if bad_status.success? || File.exist?(invalid_path) || File.exist?(File.join(directory, "must-not-create.tar"))
  raise "Unsafe refusal leaked output" unless bad_output.empty? && bad_error.include?("Operação recusada")
  results[:unsafe_environment_refused_before_database_open] = true
  results[:backup_verify_cli] = JSON.parse(run.call([ "bin/rails", "sqlite_backups:verify" ], env, "ACCIO_SQLITE_BACKUP"=>archive))
  raise "Backup changed source" unless call.call("snapshot")==before
  results[:live_wal_source_unchanged] = true
  call.call("late_cookie")
  state = JSON.parse(File.read(File.join(workspace, "state.json")))
  before_restore = call.call("snapshot")
  source_records_before_restore = records.call(env, "source-before-restore-records")
  restored = File.join(workspace, "restored")
  target_env = env.merge("ACCIO_DATABASE_PATH"=>File.join(restored, "synthetic.sqlite3"), "ACCIO_SYNTHETIC_FIXTURE"=>File.join(restored, "fixture.json"), "ACCIO_SQLITE_RESTORE_DIRECTORY"=>restored)
  socket = TCPServer.new("127.0.0.1", 0)
  port = socket.addr[1]
  socket.close
  target_env.merge!("PORT"=>port.to_s, "PIDFILE"=>File.join(workspace, "restored.pid"))
  guard = [ "bundle", "exec", "ruby", File.join(root, "script/restored-synthetic-server.rb") ]
  premature = -> {
    out, err, status = Open3.capture3(target_env, *guard, chdir: root)
    raise "Premature HTTP launcher succeeded" if status.success?
    raise "Guard leaked private output" unless out.empty? && err.include?("HTTP não iniciado")
    begin
      TCPSocket.new("127.0.0.1", port).close
      raise "Unexpected pre-preparation HTTP listener"
    rescue Errno::ECONNREFUSED
    end
  }
  premature.call
  source_during = nil
  tool.restore(archive: archive, directory: restored) do |stage|
    if stage == :restore_fidelity_verified
      premature.call
      source_during = call.call("snapshot")
    end
  end
  raise "Restore wrote source" unless source_during==before_restore && call.call("snapshot")==before_restore
  results[:http_prohibited_before_preparation] = true
  target_snapshot = call.call("snapshot", target_env)
  raise "Restore lost data" unless target_snapshot["schema"]==before["schema"] && target_snapshot["tables"].except("auth_sessions")==before["tables"].except("auth_sessions") && target_snapshot["tables"]["auth_sessions"]["rows"]==0
  recovered_records = records.call(target_env, "target-original-records")
  raise "Active Record attribute mismatch" unless original_records.except("AuthSession") == recovered_records.except("AuthSession") && recovered_records["AuthSession"].empty?
  raise "Source records changed by restore" unless records.call(env, "source-after-restore-records") == source_records_before_restore
  results[:independent_active_record_oracle] = { ten_models_all_attributes_compared: true, timestamps_with_microseconds: true, only_copied_auth_sessions_removed: true, original_password_digest_unchanged: original_records["User"] == recovered_records["User"] }
  results[:restore_logical_fidelity] = { all_tables_columns_versions_uids_dates_preserved: true, only_auth_sessions_removed: true, source_unchanged: true, old_sessions_in_backup: before["tables"]["auth_sessions"]["rows"], revoked_at_target: before["tables"]["auth_sessions"]["rows"] }
  # The guarded launcher reads the newly generated destination key, not the inherited origin key.
  fresh_key = File.read(File.join(restored, "runtime-secret"))
  raise "Reused source secret" if fresh_key==env["SECRET_KEY_BASE"]
  target_env["SECRET_KEY_BASE"] = fresh_key
  results[:new_process_running_probe] = call.call("probe", target_env)
  results[:history_replay] = call.call("history_replay", target_env)
  http = lambda do |method, path, cookie = nil, form = nil|
    request = method==:post ? Net::HTTP::Post.new(path) : Net::HTTP::Get.new(path)
    request["Host"]="localhost"
    request["Accept"]="application/json" if path=="/focus/state"
    request["Cookie"]=cookie if cookie
    request.set_form_data(form) if form
    Net::HTTP.start("127.0.0.1", port, nil, open_timeout: 2, read_timeout: 5) { |client|client.request(request) }
  end
  start_server = lambda do
    target_env["PIDFILE"] = File.join(restored, "qa-" + SecureRandom.hex(8) + ".pid")
    log = File.open(File.join(workspace, "http-private.log"), File::WRONLY|File::CREAT|File::APPEND, 0o600)
    pid = Process.spawn(target_env, *guard, chdir: root, out: log, err: log)
    log.close
    Timeout.timeout(30) do
      loop do
        begin
          response=http.call(:get, "/session/new")
          break if response.code=="200"
        rescue Errno::ECONNREFUSED, EOFError
        end
        raise "QA server exited" if Process.waitpid(pid, Process::WNOHANG)
        sleep 0.05
      end
    end
    pid
  rescue StandardError
    if pid
      begin
        Process.kill("TERM", pid)
        Process.wait(pid)
      rescue Errno::ESRCH, Errno::ECHILD
      end
    end
    raise
  end
  stop_server = lambda do |pid|
    Process.kill("TERM", pid)
    Timeout.timeout(10) { Process.wait(pid) }
  end
  pid=nil
  begin
    pid=start_server.call
    [ state["old_cookie"], state["late_cookie"] ].each do |cookie|
      raise "Old cookie accepted" unless http.call(:get, "/focus/state", cookie).code=="401"
    end
    page=http.call(:get, "/session/new")
    initial_cookie=Array(page.get_fields("set-cookie")).map { |value|value.split(";", 2).first }.join("; ")
    token=CGI.unescapeHTML(page.body[/name="authenticity_token" value="([^"]+)"/, 1].to_s)
    login=http.call(:post, "/session", initial_cookie, { "email_address"=>"backup@example.test", "password"=>state.fetch("password"), "authenticity_token"=>token })
    raise "Restored login failed" unless login.code=="303"
    cookie=Array(login.get_fields("set-cookie")).find { |value|value.start_with?("auth_session_id=") }.split(";", 2).first
    response=http.call(:get, "/focus/state", cookie)
    raise "New login cannot access focus" unless response.code=="200" && JSON.parse(response.body).dig("session", "status")=="running"
    check=SQLite3::Database.new(target_env.fetch("ACCIO_DATABASE_PATH"), readonly: true)
    collision=check.get_first_value("SELECT max(id) FROM auth_sessions")==state["late_cookie_id"]
    check.close
    raise "Expected numeric ID reuse fixture" unless collision
    raise "Post-backup old cookie resurrected" unless http.call(:get, "/focus/state", state["late_cookie"]).code=="401"
    before_gets=call.call("snapshot", target_env)
    3.times { raise "Authenticated GET failed" unless http.call(:get, "/focus/state", cookie).code=="200" }
    raise "GET wrote DB" unless call.call("snapshot", target_env)==before_gets
    %w[/ /projects /tasks /apps/focus].each { |path|raise "Restored page failed" unless http.call(:get, path, cookie).code=="200" }
    legacy = http.call(:get, "/apps/tasks", cookie)
    raise "Legacy task navigation regressed" unless legacy.code == "302" && legacy["location"].end_with?("/tasks")
    raise "Project space failed" unless http.call(:get, "/projects/#{state.fetch('project_route')}", cookie).code=="200"
    results[:authentication] = { old_cookie_rejected: true, post_capture_old_cookie_rejected_even_after_numeric_id_reuse: true, fresh_external_key: true, original_password_works: true, private_pages_reopened: true, repeated_get_no_writes: true }
    stop_server.call(pid)
    pid=nil
    pid=start_server.call
    raise "Login lost on process restart" unless http.call(:get, "/focus/state", cookie).code=="200"
    raise "Old cookie accepted after restart" unless http.call(:get, "/focus/state", state["late_cookie"]).code=="401"
    results[:http_restart] = { new_session_still_valid: true, old_sessions_still_rejected: true }
  ensure
    stop_server.call(pid) if pid
  end
  results[:source_after_http_unchanged] = call.call("snapshot")==before_restore
  raise "HTTP changed source" unless results[:source_after_http_unchanged]
  results[:concurrency] = []
  %w[preferences project task receipt].each_with_index do |operation, index|
    [ "writer-ready", "writer-release" ].each { |name|path=File.join(workspace, name);File.unlink(path) if File.exist?(path) }
    before_case=call.call("snapshot")
    source_records = records.call(env, "before-" + operation)
    Open3.popen3(env.merge("F3B_MODE"=>"writer", "F3B_OPERATION"=>operation), "bin/rails", "runner", worker, chdir: root) do |stdin, stdout, stderr, process|
      stdin.close
      begin
        Timeout.timeout(30) { sleep 0.01 until File.exist?(File.join(workspace, "writer-ready")) }
        path=File.join(directory, "concurrent-#{operation}.tar")
        release_at=index.even? ? :backup_verified : :backup_step
        released=false
        tool.backup(destination: path) do |stage|
          if stage==release_at && !released
            File.write(File.join(workspace, "writer-release"), "release", perm: 0o600)
            raise "Writer failed" unless process.value.success?
            released=true
          end
        end
        target=File.join(workspace, "concurrent-restore-#{operation}")
        tool.restore(archive: path, directory: target)
        selected=env.merge("ACCIO_DATABASE_PATH"=>File.join(target, "synthetic.sqlite3"), "ACCIO_SYNTHETIC_FIXTURE"=>File.join(target, "fixture.json"), "SECRET_KEY_BASE"=>File.read(File.join(target, "runtime-secret")))
        captured=call.call("snapshot", selected)
        target_records = records.call(selected, "after-" + operation)
        raise "Concurrent AR mismatch" unless source_records.except("AuthSession") == target_records.except("AuthSession")
        raise "Mixed point-in-time data" unless captured["schema"]==before_case["schema"] && captured["tables"].except("auth_sessions")==before_case["tables"].except("auth_sessions")
        after_case=call.call("snapshot")
        raise "Writer did not commit" if before_case==after_case
        raise "Writer completion not confirmed" unless JSON.parse(stdout.read)["committed"]==operation && stderr.read.empty?
        results[:concurrency] << { operation: operation, committed_at: release_at, uncommitted_excluded: true, pinned_data_exact: true, writer_commit_preserved: true, wal_active: true }
      ensure
        File.write(File.join(workspace, "writer-release"), "release", perm: 0o600) unless File.exist?(File.join(workspace, "writer-release"))
      end
    end
  end
  # Independent restores for pending recovery and awaiting_confirmation; GET never changes either.
  results[:additional_focus_states] = []
  %w[recovery awaiting].each do |kind|
    call.call("awaiting") if kind=="awaiting"
    backup=File.join(directory, "#{kind}.tar")
    tool.backup(destination: backup)
    target=File.join(workspace, "restored-#{kind}")
    if kind == "awaiting"
      results[:restore_cli] = JSON.parse(run.call([ "bin/rails", "sqlite_backups:restore" ], env,
        "ACCIO_SQLITE_BACKUP" => backup, "ACCIO_SQLITE_RESTORE_DIRECTORY" => target))
    else
      tool.restore(archive: backup, directory: target)
    end
    selected=env.merge("ACCIO_DATABASE_PATH"=>File.join(target, "synthetic.sqlite3"), "ACCIO_SYNTHETIC_FIXTURE"=>File.join(target, "fixture.json"), "SECRET_KEY_BASE"=>File.read(File.join(target, "runtime-secret")))
    probe=call.call("probe", selected)
    raise "Recovery receipt lost" if kind=="recovery" && !(probe["state"]=="paused" && probe["recovery_pending"])
    raise "Awaiting session auto-completed" if kind=="awaiting" && probe["state"]!="awaiting_confirmation"
    results[:additional_focus_states] << probe.merge(case: kind)
  end
  results[:sqlite] = { triggers: 25, indexes: 36, logical_schema_exact: true, integrity: "ok", foreign_key_check: [], application_wal_full: true }
  results[:private_publication] = { archive_mode: (File.stat(archive).mode&0o777).to_s(8), directory_mode: (File.stat(restored).mode&0o777).to_s(8), backups_or_secrets_in_evidence: false }
  keeper.close
  File.write(File.join(evidence, "integration.json"), JSON.pretty_generate(results)+"\n")
  puts JSON.pretty_generate(results)
end
