# Invoked only by the synthetic F3b QA orchestrator, through Rails runner.
require "json"
require "timeout"
require "sqlite3"
require Rails.root.join("test/support/focus_helpers")

workspace = ENV.fetch("F3B_WORKSPACE")
database = ActiveRecord::Base.connection_db_config.database
raise "Synthetic private database required" unless Rails.env.test? && File.realpath(database).start_with?(File.realpath(workspace) + "/") && (File.stat(workspace).mode & 0o077).zero?
mode = ENV.fetch("F3B_MODE")
state_path = File.join(workspace, "state.json")

def logical_snapshot(database)
  db = SQLite3::Database.new(database, readonly: true)
  db.execute("BEGIN")
  SqliteBackupSnapshot.read(db)
ensure
  db&.close
end

def login_cookie(user, password)
  require "action_dispatch/testing/integration"
  client = ActionDispatch::Integration::Session.new(Rails.application)
  client.host! "localhost"
  client.post "/session", params: { email_address: user.email_address, password: password }, headers: { "REMOTE_ADDR" => "127.0.0.1" }
  raise "Synthetic login failed" unless client.response.status == 303
  header = Array(client.response.headers["set-cookie"]).find { |value| value.start_with?("auth_session_id=") }
  raise "Missing synthetic cookie" unless header
  header.split(";", 2).first
end

if mode == "seed"
  password = SecureRandom.hex(24)
  user = User.create!(email_address: "backup@example.test", password: password)
  appearance = Studio.defaults.merge("theme" => "light", "wallpaper" => "ember", "accent" => "#c890f0", "music" => false, "musicExpanded" => true)
  appearance["dockOrder"].reverse!
  appearance["dockHidden"] = [ appearance["dockOrder"].first ]
  appearance["widgets"].reverse!
  appearance["widgets"].first.merge!("span" => 8, "visible" => false)
  store = AppearancePreferences.new(user)
  store.bootstrap(legacy: appearance, raw: "synthetic backup root cookie")
  store.bootstrap(legacy: nil, raw: "synthetic opaque retained cookie", action: "keep_database", version: user.user_preference.reload.lock_version)
  pref = user.user_preference.reload
  backup = pref.legacy_cookie_backup.deep_dup
  backup["future-field"] = { "custom" => [ 1, nil, "á" ] }
  pref.update!(focus_duration_seconds: 2700, project_library_status: "paused", project_library_sort: "recent", legacy_cookie_backup: backup)
  first = user.projects.create!(uid: "project/á?%#项目", name: "Original")
  first.update!(name: "Renamed synthetic", description: "Original content <b>kept</b>", favorite: true, icon: "code", color: "#aabbcc")
  archived = user.projects.create!(uid: "archived-legacy-42", name: "Archived synthetic", status: "paused")
  target = user.projects.create!(uid: "target", name: "Move target")
  personal = user.tasks.create!(uid: "task-personal", title: "Personal task", priority: "high")
  contextual = user.tasks.create!(uid: "task/ç?%#项目", title: "Context task", project: first)
  completed = user.tasks.create!(uid: "task-completed", title: "Completed task", project: first, status: "completed", completed_at: Time.current)
  user.tasks.create!(uid: "task-archived", title: "Archived task", project: archived)
  reference = user.project_references.create!(uid: "reference/á?%", project: first, title: "Reference <script>text</script>", kind: "link", url: "https://docs.example.test/path?q=%C3%A1#part", description: "Original reference text")
  reference.update!(description: "Edited original content & <tag>")
  user.project_references.create!(uid: "material", project: archived, title: "Text material", kind: "material", description: "Material without URL")
  archived.archive!
  clock = FocusTestClock.new
  engine = FocusCommands.new(user, time: FocusTime.new(clock: clock, observations: FocusTime::Observations.new))
  history = user.focus_sessions.create!(uid: "history/完成", status: "awaiting_confirmation", elapsed_seconds: 1500, duration_seconds: 1500, started_at: clock.wall - 1500)
  completion = { uid: history.uid, command_id: "history_complete", version: history.lock_version, kind: "complete", parameters: { "action" => "confirm" } }
  engine.command(**completion)
  cancelled = user.focus_sessions.create!(uid: "history-cancelled", duration_seconds: 2700)
  engine.command(uid: cancelled.uid, command_id: "history_cancel", version: 0, kind: "reset", parameters: { "action" => "cancel" })
  context = { "project_uid" => first.uid, "project_version" => first.reload.lock_version, "task_uid" => contextual.uid, "task_version" => contextual.lock_version }
  engine.prepare(intent: engine.issue(context: context, duration: 1500), command_id: "running_start", version: 0, action: "start_new")
  running = user.focus_sessions.occupying.first
  clock.advance(10)
  engine.command(uid: running.uid, command_id: "checkpoint_pause", version: running.lock_version, kind: "pause", parameters: { "action" => "pause" })
  running.reload
  engine.command(uid: running.uid, command_id: "checkpoint_resume", version: running.lock_version, kind: "start", parameters: { "action" => "resume" })
  # Context history remains first project even after the task moves.
  TaskCommands.new(user).change(contextual.uid, version: contextual.lock_version, operation: "edit", attributes: { "title" => contextual.title }, destination: target.uid)
  raise "Historical context changed" unless running.reload.project_id == first.id && contextual.reload.project_id == target.id
  user.auth_sessions.create!(expires_at: Time.current - 1.hour)
  cookie = login_cookie(user, password)
  File.write(state_path, JSON.generate({ password: password, old_cookie: cookie, old_cookie_id: AuthSession.maximum(:id), completion: completion, task_route: personal.to_param, project_route: first.to_param }), perm: 0o600)
  File.chmod(0o600, database)
  puts JSON.generate({ seeded: true, focus: running.reload.status, confirmed_checkpoint: running.elapsed_seconds, tables: logical_snapshot(database)["tables"].transform_values { |t|t["rows"] } })
elsif mode == "late_cookie"
  state = JSON.parse(File.read(state_path))
  state["late_cookie"] = login_cookie(User.first, state.fetch("password"))
  state["late_cookie_id"] = AuthSession.maximum(:id)
  File.write(state_path, JSON.generate(state))
  puts JSON.generate({ post_capture_cookie_created: true })
elsif mode == "snapshot"
  # Private JSON goes only to the orchestrator's memory, not versionable evidence.
  puts JSON.generate(logical_snapshot(database))
elsif mode == "records"
  # Independent oracle: Active Record attributes, not the backup fingerprint implementation.
  path = File.expand_path(ENV.fetch("F3B_RECORDS_PATH"))
  raise "Private new comparison file required" unless path.start_with?(File.realpath(workspace) + "/") && !File.exist?(path)
  rows = ActiveRecord::Base.transaction do
    ActiveRecord::Base.connection.materialize_transactions
    [ User, Project, Task, ProjectReference, UserPreference, DockShortcut, WidgetPlacement, FocusSession, FocusCommand, AuthSession ].to_h do |model|
      [ model.name, model.order(:id).map { |row| row.attributes.transform_values { |value| value.respond_to?(:iso8601) ? value.iso8601(6) : value } } ]
    end
  end
  File.open(path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) { |file| file.write(JSON.generate(rows)) }
  puts JSON.generate({ private_comparison_written: true })
elsif mode == "writer"
  operation = ENV.fetch("F3B_OPERATION")
  user = User.first
  ActiveRecord::Base.transaction do
    ActiveRecord::Base.connection.materialize_transactions
    case operation
    when "preferences"
      store = AppearancePreferences.new(user)
      current = store.read
      store.update(current[:appearance].merge("theme" => "dark"), version: current[:version])
    when "project"
      user.projects.create!(uid: "concurrent-project", name: "Concurrent committed project")
    when "task"
      task = user.tasks.find_by!(uid: "task-personal")
      TaskCommands.new(user).change(task.uid, version: task.lock_version, operation: "edit", attributes: { "title" => "Concurrent task edit" })
    when "receipt"
      session = user.focus_sessions.occupying.first
      FocusCommands.new(user).command(uid: session.uid, command_id: "concurrent_receipt", version: session.lock_version, kind: "pause", parameters: { "action" => "reconcile" })
    end
    File.write(File.join(workspace, "writer-ready"), "ready", perm: 0o600)
    Timeout.timeout(30) { sleep 0.01 until File.exist?(File.join(workspace, "writer-release")) }
  end
  puts JSON.generate({ committed: operation })
elsif mode == "probe"
  user = User.first
  before = logical_snapshot(database)
  state = FocusCommands.new(user).read
  after = logical_snapshot(database)
  raise "GET-style focus read wrote state" unless before == after
  raise "Duplicate slot" unless user.focus_sessions.occupying.count == 1
  raise "Automatic completion" unless user.focus_sessions.where(status: "completed").count == 1
  c = ActiveRecord::Base.connection
  raise "Unsafe pragmas" unless [ c.select_value("PRAGMA foreign_keys"), c.select_value("PRAGMA journal_mode"), c.select_value("PRAGMA synchronous") ] == [ 1, "wal", 2 ]
  raise "Integrity failure" unless c.select_value("PRAGMA integrity_check") == "ok" && c.select_all("PRAGMA foreign_key_check").empty?
  puts JSON.generate({ state: state.dig("session", "status"), checkpoint: state.dig("session", "elapsed_seconds"), recovery_pending: !state["recovery"].nil?, focus_read_did_not_write: true, completed_history: 1, global_occupants: 1, wal_full_foreign_keys: true })
elsif mode == "history_replay"
  state = JSON.parse(File.read(state_path))
  command = state.fetch("completion").symbolize_keys
  before = logical_snapshot(database)
  result = FocusCommands.new(User.first).command(**command)
  raise "History replay not recognized" unless result["replayed"]
  raise "Replay changed state" unless logical_snapshot(database) == before
  begin
    FocusCommand.connection.execute("UPDATE focus_commands SET result='{}' WHERE command_id='history_complete'")
    raise "Receipt mutable"
  rescue ActiveRecord::StatementInvalid
  end
  begin
    FocusSession.connection.execute("UPDATE focus_sessions SET uid='replaced' WHERE status='completed'")
    raise "History mutable"
  rescue ActiveRecord::StatementInvalid
  end
  raise "SQL adversarial change persisted" unless logical_snapshot(database) == before
  puts JSON.generate({ historical_replay_immutable: true, no_duplicate_receipt: true })
elsif mode == "awaiting"
  user = User.first
  session = user.focus_sessions.occupying.first
  FocusCommands.new(user).command(uid: session.uid, command_id: "cancel_for_awaiting_fixture", version: session.lock_version, kind: "reset", parameters: { "action" => "cancel" })
  user.focus_sessions.create!(uid: "awaiting-fixture", status: "awaiting_confirmation", duration_seconds: 2700, elapsed_seconds: 2700, started_at: Time.current - 2700)
  puts JSON.generate({ awaiting_fixture: true })
end
