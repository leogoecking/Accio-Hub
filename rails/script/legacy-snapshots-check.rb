#!/usr/bin/env ruby
require "bundler/setup"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "timeout"
require "digest"

root = File.expand_path("..", __dir__)
evidence = ENV.fetch("ACCIO_QA_EVIDENCE")
FileUtils.mkdir_p(evidence)
results = {}
Dir.mktmpdir("accio-f3a-process-") do |workspace|
  source = File.join(workspace, "source")
  target = File.join(workspace, "target")
  starting = File.join(workspace, "starting")
  [ source, target, starting ].each { |path| Dir.mkdir(path, 0o700) }
  make_env = lambda do |directory|
    fixture = File.join(directory, "fixture.json")
    File.write(fixture, JSON.generate({ format: "accio-f3a-synthetic", version: 1, database: "synthetic.sqlite3" }), perm: 0o600)
    { "RAILS_ENV" => "test", "ACCIO_DATABASE_PATH" => File.join(directory, "synthetic.sqlite3"), "ACCIO_SYNTHETIC_FIXTURE" => fixture, "F3A_WORKSPACE" => workspace }
  end
  env = make_env.call(source)
  destination_env = make_env.call(target)
  starting_env = make_env.call(starting)
  runner = File.join(workspace, "runner.rb")
  File.write(runner, <<~'CODE', perm: 0o600)
    require "digest"
    require "json"
    require "timeout"
    workspace = ENV.fetch("F3A_WORKSPACE")
    database = ActiveRecord::Base.connection_db_config.database
    raise "Not synthetic" unless Rails.env.test? && database.start_with?(workspace + "/")
    mode = ENV.fetch("F3A_MODE")
    logical = -> {
      { preferences: UserPreference.order(:id).map(&:attributes), dock: DockShortcut.order(:id).map(&:attributes), widgets: WidgetPlacement.order(:id).map(&:attributes) }
    }
    if mode == "seed"
      user = User.create!(email_address: "synthetic@example.test", password: SecureRandom.hex(20))
      store = AppearancePreferences.new(user)
      store.bootstrap(legacy: Studio.defaults.merge("theme" => "light"), raw: "synthetic root cookie")
      store.bootstrap(legacy: nil, raw: "synthetic invalid encrypted cookie", action: "keep_database", version: user.user_preference.reload.lock_version)
      store.bootstrap(legacy: Studio.defaults, raw: "synthetic additional valid cookie", action: "keep_database", version: user.user_preference.reload.lock_version)
      pref = user.user_preference.reload
      backup = pref.legacy_cookie_backup.deep_dup
      backup["future-extension"] = { "unknown" => [ 4, "ação", false, nil ] }
      backup["retained_candidates"]["opaque"] = { "raw" => [ 1, 2 ], "custom" => true }
      pref.update!(legacy_cookie_backup: backup)
      File.chmod(0o600, database)
      File.write(File.join(workspace, "before.json"), JSON.generate(logical.call), perm: 0o600)
      puts JSON.generate({ seeded: true, candidates: 4 })
    elsif mode == "empty_seed"
      User.create!(email_address: "empty@example.test", password: SecureRandom.hex(20))
      puts JSON.generate({ empty_profile: true })
    elsif mode == "unchanged"
      raise "Aggregate modified by read/export" unless JSON.parse(File.read(File.join(workspace, "before.json"))) == JSON.parse(JSON.generate(logical.call))
      puts JSON.generate({ entire_aggregate_identical: true })
    elsif mode == "recover"
      raise "Existing operational aggregate" unless [UserPreference, DockShortcut, WidgetPlacement, User].all? { |model| model.count.zero? }
      archive = LegacySnapshotArchive.new(fixture: ENV.fetch("SOURCE_FIXTURE"), database: ENV.fetch("SOURCE_DATABASE"), environment: "test", checkout: Rails.root.parent.to_s)
      content = archive.verify(ENV.fetch("ARCHIVE"))
      backup = JSON.parse(archive.original(content.fetch("capture")))
      UserPreference.transaction do
        raise "Existing preference" if UserPreference.exists?
        user = User.create!(email_address: "recovered@example.test", password: SecureRandom.hex(20))
      # Deliberate selection, revalidation and application of ONE valid candidate into an empty profile.
      AppearancePreferences.validate!(backup.fetch("value"))
      raise "Invalid digest" unless backup["valid"] == true && Digest::SHA256.hexdigest(backup.fetch("raw")) == backup.fetch("digest")
      state = AppearancePreferences.new(user).bootstrap(legacy: backup.fetch("value"), raw: backup.fetch("raw"))
      raise "Value changed" unless state[:appearance] == backup.fetch("value")
      # Preserve all original candidates/unknown fields as evidence in the NEW synthetic profile only.
      UserPreference.first.update!(legacy_cookie_backup: backup)
      raise "Evidence lost" unless UserPreference.first.reload.legacy_cookie_backup == backup
      end
      File.chmod(0o600, database)
      raise "Opaque data applied" unless UserPreference.first.theme == backup.fetch("value").fetch("theme")
      # Existing profile cannot be a recovery target: this proof refuses it before any writes.
      raise "Missing recovered rows" unless [UserPreference.count,DockShortcut.count,WidgetPlacement.count] == [1,8,7]
      File.write(File.join(workspace, "recovered.json"), JSON.generate(logical.call), perm: 0o600)
      puts JSON.generate({ empty_profile_recovered: true, selected_value_revalidated: true, all_candidates_and_unknown_fields_preserved: true, invalid_candidates_opaque_only: true })
    elsif mode == "recovered_unchanged"
      raise "Recovery duplicated" unless JSON.parse(File.read(File.join(workspace, "recovered.json"))) == JSON.parse(JSON.generate(logical.call))
      puts JSON.generate({ recovered_profile_unchanged: true })
    elsif mode == "writer"
      user = User.first
      store = AppearancePreferences.new(user)
      preference = user.user_preference
      operation = ENV.fetch("F3A_OPERATION")
      # Deliberately hold a real writer transaction while inventory/export captures a WAL read snapshot.
      UserPreference.transaction do
        UserPreference.connection.materialize_transactions
        before = store.read
        case operation
        when "theme"
          store.update(before[:appearance].merge("theme" => before[:appearance]["theme"] == "light" ? "dark" : "light"), version: before[:version])
        when "preset"
          preference.reload.update!(focus_duration_seconds: preference.focus_duration_seconds == 1500 ? 2700 : 1500)
        when "bootstrap_empty"
          store.bootstrap(legacy: Studio.defaults, raw: "synthetic initial bootstrap")
        when "bootstrap"
          store.bootstrap(legacy: nil, raw: "concurrent synthetic candidate", action: "keep_database", version: before[:version])
        end
        File.write(File.join(workspace, "writer-ready"), "ready", perm: 0o600)
        Timeout.timeout(30) { sleep 0.01 until File.exist?(File.join(workspace, "writer-release")) }
      end
      puts JSON.generate({ writer_committed: operation })
    elsif mode == "fingerprint"
      c = ActiveRecord::Base.connection
      archive = LegacySnapshotArchive.new(fixture: ENV.fetch("ACCIO_SYNTHETIC_FIXTURE"), database: database, environment: "test", checkout: Rails.root.parent.to_s)
      captured = archive.capture
      objects = c.select_all("SELECT type,name,sql FROM sqlite_master WHERE type IN ('trigger','index') ORDER BY type,name").to_a
      raise "Wrong objects" unless objects.count { |r| r["type"] == "trigger" } == 25 && objects.count { |r| r["type"] == "index" } == 36
      raise "Corrupt DB" unless c.select_value("PRAGMA integrity_check") == "ok" && c.select_all("PRAGMA foreign_key_check").empty?
      raise "Pragmas" unless [c.select_value("PRAGMA foreign_keys"),c.select_value("PRAGMA journal_mode"),c.select_value("PRAGMA synchronous")] == [1,"wal",2]
      puts JSON.generate({ capture_sha256: Digest::SHA256.hexdigest(JSON.generate(captured)), version: captured.dig("record","lock_version"), triggers: 25, indexes: 36, objects_sha256: Digest::SHA256.hexdigest(JSON.generate(objects)), integrity: "ok", foreign_keys: true, wal_full: true })
    end
  CODE
  run = lambda do |args, selected_env = env, changes = {}|
    output, error, status = Open3.capture3(selected_env.merge(changes), *args, chdir: root)
    raise "Synthetic command failed (#{args.first(2).join(' ')}): #{error.lines.first}" unless status.success?
    output
  end
  [ env, destination_env, starting_env ].each do |selected|
    run.call([ "bin/rails", "db:schema:load" ], selected)
    File.chmod(0o600, selected.fetch("ACCIO_DATABASE_PATH"))
  end
  call = ->(mode, selected = env, changes = {}) { run.call([ "bin/rails", "runner", runner ], selected, changes.merge("F3A_MODE" => mode)) }
  results[:seed] = JSON.parse(call.call("seed"))
  results[:empty_seed] = JSON.parse(call.call("empty_seed", starting_env))
  before = JSON.parse(call.call("fingerprint"))
  export_path = File.join(source, "archive.json")
  results[:inventory] = JSON.parse(run.call([ "bin/rails", "legacy_snapshots:inventory" ]))
  results[:export] = JSON.parse(run.call([ "bin/rails", "legacy_snapshots:export" ], env, "ACCIO_SNAPSHOT_DESTINATION" => export_path))
  results[:reopen] = JSON.parse(run.call([ "bin/rails", "legacy_snapshots:verify" ], env, "ACCIO_SNAPSHOT_ARCHIVE" => export_path))
  results[:unchanged] = JSON.parse(call.call("unchanged"))
  raise "Read changed capture" unless before == JSON.parse(call.call("fingerprint"))
  original_digest = Digest::SHA256.file(export_path).hexdigest
  results[:recovery] = JSON.parse(call.call("recover", destination_env, { "SOURCE_DATABASE" => env.fetch("ACCIO_DATABASE_PATH"), "SOURCE_FIXTURE" => env.fetch("ACCIO_SYNTHETIC_FIXTURE"), "ARCHIVE" => export_path }))
  _, _, repeat_status = Open3.capture3(destination_env.merge("F3A_MODE" => "recover", "SOURCE_DATABASE" => env.fetch("ACCIO_DATABASE_PATH"), "SOURCE_FIXTURE" => env.fetch("ACCIO_SYNTHETIC_FIXTURE"), "ARCHIVE" => export_path), "bin/rails", "runner", runner, chdir: root)
  raise "Recovery overwrote initialized profile" if repeat_status.success?
  results[:recovery_existing_refused] = true
  results[:recovery_reopen] = JSON.parse(call.call("recovered_unchanged", destination_env))
  raise "Export changed during recovery" unless Digest::SHA256.file(export_path).hexdigest == original_digest
  results[:concurrency] = []
  %w[theme preset bootstrap bootstrap_empty].each do |operation|
    selected = operation == "bootstrap_empty" ? starting_env : env
    [ "writer-ready", "writer-release" ].each { |name| File.unlink(File.join(workspace, name)) if File.exist?(File.join(workspace, name)) }
    before = JSON.parse(call.call("fingerprint", selected))
    reader = nil
    Open3.popen3(selected.merge("F3A_MODE" => "writer", "F3A_OPERATION" => operation), "bin/rails", "runner", runner, chdir: root) do |stdin, stdout, stderr, process|
      stdin.close
      begin
        Timeout.timeout(30) { sleep 0.01 until File.exist?(File.join(workspace, "writer-ready")) }
        path = File.join(source, "concurrent-#{operation}.json")
        run.call([ "bin/rails", "legacy_snapshots:export" ], selected, "ACCIO_SNAPSHOT_DESTINATION" => path)
        # Separate CLI process, exact single-SELECT bytes/metadata must match the committed before state.
        inspection = File.join(workspace, "inspect.rb")
        File.write(inspection, 'require_relative '+File.join(root, "app/services/legacy_snapshot_archive").inspect+"\n"+ 'a=LegacySnapshotArchive.new(fixture:ENV.fetch("ACCIO_SYNTHETIC_FIXTURE"),database:ENV.fetch("ACCIO_DATABASE_PATH"),environment:"test",checkout:'+File.dirname(root).inspect+');c=a.verify(ENV.fetch("ARCHIVE"));puts JSON.generate({capture_sha256:Digest::SHA256.hexdigest(JSON.generate(c.fetch("capture"))),version:c.dig("capture","record","lock_version")})', perm: 0o600)
        reader = JSON.parse(run.call([ "bundle", "exec", "ruby", inspection ], selected, "ARCHIVE" => path))
        raise "Mixed concurrent capture" unless reader.fetch("capture_sha256") == before.fetch("capture_sha256")
      ensure
        File.write(File.join(workspace, "writer-release"), "release", perm: 0o600)
      end
      raise "Writer failed" unless process.value.success?
      raise "Writer output missing" unless JSON.parse(stdout.read)["writer_committed"] == operation
      raise "Unexpected writer stderr" unless stderr.read.empty?
    end
    after = JSON.parse(call.call("fingerprint", selected))
    advanced = before["version"].nil? ? after["version"] == 0 : after["version"] > before["version"]
    raise "Writer did not change CAS" unless advanced
    raise "SQL objects changed" unless before.fetch("objects_sha256") == after.fetch("objects_sha256")
    results[:concurrency] << { operation: operation, before_version: before["version"], captured_version: reader["version"], after_version: after["version"], coherent_point_in_time: true }
  end
  results[:integrity] = JSON.parse(call.call("fingerprint"))
  results[:target_integrity] = JSON.parse(call.call("fingerprint", destination_env))
  # Refusal occurs without :environment and without opening a default operational database.
  bad_env = env.merge("RAILS_ENV" => "development", "ACCIO_DATABASE_PATH" => File.join(workspace, "must-not-be-created.sqlite3"))
  output, _, status = Open3.capture3(bad_env, "bin/rails", "legacy_snapshots:inventory", chdir: root)
  raise "Unsafe environment accepted" if status.success? || File.exist?(bad_env.fetch("ACCIO_DATABASE_PATH"))
  raise "Unexpected private output" unless output.empty?
  results[:unsafe_environment_refused_before_database_open] = true
  results[:private_files] = { directory_mode: (File.stat(source).mode & 0o777).to_s(8), archive_mode: (File.stat(export_path).mode & 0o777).to_s(8) }
  results[:exports_in_versionable_evidence] = false
  results[:source_sqlite_not_restored_or_replaced] = true
  File.write(File.join(evidence, "round-trip-and-concurrency.json"), JSON.pretty_generate(results)+"\n")
  puts JSON.pretty_generate(results)
end
