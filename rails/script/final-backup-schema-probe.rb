#!/usr/bin/env ruby
# Synthetic F5 reproduction only; no edits to domain or backup contracts.
require "bundler/setup"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "securerandom"
require_relative "../app/services/synthetic_sqlite_backup"

root = File.expand_path("..", __dir__)
evidence = ENV.fetch("ACCIO_QA_EVIDENCE")
FileUtils.mkdir_p(evidence)
contract = JSON.parse(File.read(File.join(root, "config/sqlite_backup_contract.json")))
results = []
Dir.mktmpdir("accio-f5-schema-") do |directory|
  %w[test development].each do |mode|
    source = File.join(directory, mode)
    Dir.mkdir(source, 0o700)
    database = File.join(source, "synthetic.sqlite3")
    fixture = File.join(source, "fixture.json")
    File.write(fixture, JSON.generate({ format: "accio-f3a-synthetic", version: 1, database: "synthetic.sqlite3" }), perm: 0o600)
    environment = { "RAILS_ENV" => mode, "ACCIO_DATABASE_PATH" => database, "SECRET_KEY_BASE" => SecureRandom.hex(64) }
    _output, _error, status = Open3.capture3(environment, "bin/rails", "db:schema:load", chdir: root)
    raise "Synthetic setup failed" unless status.success?
    File.chmod(0o600, database)
    db = SQLite3::Database.new(database, readonly: true)
    before = SqliteBackupSnapshot.read(db)
    copied_schema = JSON.parse(JSON.generate(before.fetch("schema")))
    tagged = copied_schema.fetch("objects").filter_map do |row|
      next unless row[3]&.end_with?(" /*application='AccioHub'*/")
      row[3] = row[3].delete_suffix(" /*application='AccioHub'*/")
      row[1]
    end
    tool = SyntheticSqliteBackup.new(fixture: fixture, database: database, environment: "test", checkout: File.dirname(root))
    begin
      tool.backup(destination: File.join(source, "probe.tar"))
      result = "accepted"
    rescue SyntheticSqliteBackup::Invalid => exception
      result = exception.message
    end
    after = SqliteBackupSnapshot.read(db)
    raise "Source changed during backup attempt" unless before == after
    check = { environment: mode, schema_sha256: before.fetch("schema_sha256"),
      accepted_schema_hash: contract.fetch("schema_sha256").include?(before.fetch("schema_sha256")),
      hypothetical_sql_comment_removed_hash: SqliteBackupSnapshot.fingerprint(copied_schema),
      hypothetical_hash_matches_contract: contract.fetch("schema_sha256").include?(SqliteBackupSnapshot.fingerprint(copied_schema)),
      sql_tagged_objects: tagged, backup_result: result, source_unchanged: true,
      integrity: db.get_first_value("PRAGMA integrity_check"), foreign_key_violations: db.execute("PRAGMA foreign_key_check").size,
      triggers: before.fetch("schema").fetch("objects").count { |row| row[0] == "trigger" },
      indexes: before.fetch("schema").fetch("objects").count { |row| row[0] == "index" } }
    db.close
    results << check
  end
end
raise "Expected reproduction not observed" unless results[0][:backup_result] == "accepted" &&
  results[1][:backup_result] == "Schema incompatível com esta versão da aplicação" &&
  results[1][:hypothetical_hash_matches_contract]
File.write(File.join(evidence, "schema-probe.json"), JSON.pretty_generate(results) + "\n")
puts JSON.pretty_generate(results)
