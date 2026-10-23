#!/usr/bin/env ruby
# Four NEW private synthetic fixtures. Administrative commands always run in test.
require "bundler/setup"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "securerandom"
require_relative "../app/services/synthetic_sqlite_backup"

root = File.expand_path("..", __dir__)
evidence = ENV.fetch("ACCIO_QA_EVIDENCE")
phase = ENV.fetch("ACCIO_QA_PHASE")
raise "Use before/after explicitly" unless %w[before after].include?(phase)
contract_path = File.join(root, "config/sqlite_backup_contract.json")
contract_bytes = File.binread(contract_path)
contract = JSON.parse(contract_bytes)
FileUtils.mkdir_p(evidence)
results = []
structures = {}
Dir.mktmpdir("accio-f501-matrix-") do |workspace|
  %w[test development].product(%w[db:migrate db:schema:load]).each do |creation, preparation|
    directory = File.join(workspace, "#{creation}-#{preparation.tr(':', '-')}")
    Dir.mkdir(directory, 0o700)
    database = File.join(directory, "synthetic.sqlite3")
    fixture = File.join(directory, "fixture.json")
    File.write(fixture, JSON.generate({ format: "accio-f3a-synthetic", version: 1, database: "synthetic.sqlite3" }), perm: 0o600)
    environment = { "RAILS_ENV" => creation, "ACCIO_DATABASE_PATH" => database,
      "SECRET_KEY_BASE" => SecureRandom.hex(64) }
    environment["SCHEMA"] = File.join(directory, "generated-schema.rb") if preparation == "db:migrate"
    _, error, status = Open3.capture3(environment, "bin/rails", preparation, chdir: root)
    raise "Synthetic preparation failed: #{error.lines.first}" unless status.success?
    File.chmod(0o600, database)
    if phase == "after"
      seed_environment = environment.merge("RAILS_ENV" => "test", "F3B_WORKSPACE" => directory, "F3B_MODE" => "seed")
      _, seed_error, seed_status = Open3.capture3(seed_environment, "bin/rails", "runner", "script/sqlite-backups-worker.rb", chdir: root)
      raise "Synthetic domain seed failed: #{seed_error.lines.first}" unless seed_status.success?
    end
    db = SQLite3::Database.new(database, readonly: true)
    before = SqliteBackupSnapshot.read(db)
    structures[[ creation, preparation ]] = before.fetch("schema")
    archive = File.join(directory, "matrix.tar")
    admin = environment.merge("RAILS_ENV" => "test", "ACCIO_SYNTHETIC_FIXTURE" => fixture, "ACCIO_SQLITE_BACKUP" => archive)
    output, error, status = Open3.capture3(admin, "bin/rails", "sqlite_backups:create", chdir: root)
    verified = nil
    if status.success?
      verified_output, _, verification = Open3.capture3(admin, "bin/rails", "sqlite_backups:verify", chdir: root)
      raise "Produced TAR failed verification" unless verification.success?
      verified = JSON.parse(verified_output)
      raise "Backup receipt mismatch" unless verified == JSON.parse(output)
    end
    row = { creation_environment: creation, preparation: preparation, admin_environment: "test",
      schema_sha256: before.fetch("schema_sha256"), listed: contract.fetch("schema_sha256").include?(before.fetch("schema_sha256")),
      migrations_sha256: before.fetch("tables").fetch("schema_migrations").fetch("sha256"),
      migrations_match: before.fetch("tables").fetch("schema_migrations").fetch("sha256") == contract.fetch("migrations_sha256"),
      triggers: before.fetch("schema").fetch("objects").count { |o| o[0] == "trigger" },
      indexes: before.fetch("schema").fetch("objects").count { |o| o[0] == "index" },
      integrity: db.get_first_value("PRAGMA integrity_check"), foreign_key_violations: db.execute("PRAGMA foreign_key_check").size,
      backup: status.success? ? "accepted" : "rejected", tar_verified: !verified.nil?,
      source_unchanged: SqliteBackupSnapshot.read(db) == before,
      private_directory: (File.stat(directory).mode & 0o777) == 0o700, private_database: (File.stat(database).mode & 0o777) == 0o600 }
    raise "Unexpected administrative output" unless status.success? || error.include?("Operação recusada")
    if phase == "after" && status.success?
      tool = SyntheticSqliteBackup.new(fixture: fixture, database: database, environment: "test", checkout: File.dirname(root))
      restored = File.join(directory, "restored")
      fidelity_before_security = false
      restoration = tool.restore(archive: archive, directory: restored) do |stage|
        next unless stage == :restore_fidelity_verified
        candidates = Dir.glob(File.join(restored, "**", "synthetic.sqlite3"), File::FNM_DOTMATCH)
        raise "Expected one private staged destination" unless candidates.size == 1
        staged = SQLite3::Database.new(candidates.first, readonly: true)
        raise "Pre-security data mismatch" unless SqliteBackupSnapshot.read(staged) == before
        staged.close
        fidelity_before_security = true
      end
      target = SQLite3::Database.new(File.join(restored, "synthetic.sqlite3"), readonly: true)
      recovered = SqliteBackupSnapshot.read(target)
      target.close
      raise "Restoration changed schema/domain" unless recovered.fetch("schema") == before.fetch("schema") &&
        recovered.fetch("tables").except("auth_sessions") == before.fetch("tables").except("auth_sessions")
      raise "Copied sessions not revoked" unless recovered.fetch("tables").fetch("auth_sessions").fetch("rows").zero? && restoration.fetch("revoked_sessions").positive?
      runtime = File.binread(File.join(restored, "runtime-secret"))
      raise "Runtime key reused" if runtime == environment.fetch("SECRET_KEY_BASE")
      row.merge!(restore_prepared: restoration.fetch("prepared"), fidelity_before_security: fidelity_before_security,
        after_security_only_auth_sessions_differ: true, revoked_sessions: restoration.fetch("revoked_sessions"),
        runtime_key_separate: true, source_unchanged_after_restore: SqliteBackupSnapshot.read(db) == before)
    end
    results << row
    db.close
  end
end
comparisons = %w[db:migrate db:schema:load].map do |preparation|
  baseline = structures.fetch([ "test", preparation ])
  development = structures.fetch([ "development", preparation ])
  raise "Foreign key divergence" unless baseline.fetch("foreign_keys") == development.fetch("foreign_keys")
  left = baseline.fetch("objects")
  right = development.fetch("objects")
  raise "Object name/order divergence" unless left.map { |o| o.first(3) } == right.map { |o| o.first(3) }
  changes = left.zip(right).filter_map do |test, dev|
    next if test == dev
    raise "Additional structural divergence" unless test[0] == "index" && dev[3] == test[3] + " /*application='AccioHub'*/"
    test[1]
  end
  raise "Expected exactly 34 annotated indexes" unless changes.size == 34
  { preparation: preparation, annotated_indexes: changes, foreign_keys_identical: true,
    all_other_schema_objects_identical: true, ddl_modified: false }
end
File.write(File.join(evidence, "#{phase}-matrix.json"), JSON.pretty_generate({ phase: phase, rows: results, comparisons: comparisons }) + "\n")
raise "Contract changed during matrix" unless File.binread(contract_path) == contract_bytes
results.each do |row|
  expected_hashes = {
    [ "test", "db:migrate" ] => "621ee16d32be40ae482a50c92cc8a3fc55fc92d5aa27186e34506e1b77f529e8",
    [ "test", "db:schema:load" ] => "c8752c5aabda1b9064750d8982648e89eaacfb4d68d117f36c3ad1e77ca542f7",
    [ "development", "db:migrate" ] => "edc335eb6c71b2062b5a65c4563fcbe0fe341deaa5ca55ac7383f8dd92ec5751",
    [ "development", "db:schema:load" ] => "b42e0bb59d064152d690856959275801ae4f1e034e291765d56bbc1874986470"
  }
  expected = [ expected_hashes.fetch([ row[:creation_environment], row[:preparation] ]) ]
  raise "Unexpected legitimate fingerprint" unless expected.include?(row[:schema_sha256])
  raise "Integrity/immutability failure" unless row.values_at(:migrations_match, :source_unchanged, :private_directory, :private_database).all? &&
    row[:triggers] == 25 && row[:indexes] == 36 && row[:integrity] == "ok" && row[:foreign_key_violations].zero?
  if phase == "after"
    raise "Restore verification failed" unless row.values_at(:restore_prepared, :fidelity_before_security,
      :after_security_only_auth_sessions_differ, :runtime_key_separate, :source_unchanged_after_restore).all?
  end
  accepted = phase == "after" || row[:creation_environment] == "test"
  raise "Unexpected backup outcome" unless row[:backup] == (accepted ? "accepted" : "rejected") && row[:tar_verified] == accepted
end
puts JSON.pretty_generate(results)
