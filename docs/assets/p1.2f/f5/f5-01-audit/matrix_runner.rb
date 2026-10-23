#!/usr/bin/env ruby
require "bundler/setup"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "securerandom"
require "sqlite3"
require "digest"

rails_root = File.expand_path("../../../../../rails", __dir__)
output_dir = File.expand_path(__dir__)
contract_file = File.join(rails_root, "config/sqlite_backup_contract.json")
contract = JSON.parse(File.read(contract_file))

require_relative File.join(rails_root, "app/services/sqlite_backup_snapshot")
require_relative File.join(rails_root, "app/services/synthetic_sqlite_backup")

puts "=== EXECUTING MATRIX OF 4 SYNTHETIC DATABASES ==="

matrix = [
  { env: "test", prep: "db:migrate" },
  { env: "test", prep: "db:schema:load" },
  { env: "development", prep: "db:migrate" },
  { env: "development", prep: "db:schema:load" }
]

matrix_results = []

Dir.mktmpdir("accio-f5-matrix-") do |workdir|
  matrix.each_with_index do |item, idx|
    env_name = item[:env]
    prep_task = item[:prep]
    sub_dir = File.join(workdir, "#{env_name}_#{prep_task.tr(':', '_')}")
    Dir.mkdir(sub_dir, 0o700)
    db_path = File.join(sub_dir, "synthetic.sqlite3")
    fixture_path = File.join(sub_dir, "fixture.json")

    File.write(fixture_path, JSON.generate({
      format: "accio-f3a-synthetic",
      version: 1,
      database: "synthetic.sqlite3"
    }), perm: 0o600)

    rails_env = {
      "RAILS_ENV" => env_name,
      "ACCIO_DATABASE_PATH" => db_path,
      "SECRET_KEY_BASE" => SecureRandom.hex(64)
    }

    # Execute Rails prep command
    out, err, status = Open3.capture3(rails_env, "bin/rails", prep_task, chdir: rails_root)
    raise "Rails preparation failed for #{env_name} #{prep_task}: #{err}" unless status.success?

    File.chmod(0o600, db_path)
    db = SQLite3::Database.new(db_path, readonly: true)

    # 1. Structural inspection
    integrity = db.get_first_value("PRAGMA integrity_check")
    fk_violations = db.execute("PRAGMA foreign_key_check")
    migrations = db.execute("SELECT version FROM schema_migrations ORDER BY version").flatten
    structure = SqliteBackupSnapshot.schema(db)
    literal_fingerprint = SqliteBackupSnapshot.fingerprint(structure)
    snapshot_before = SqliteBackupSnapshot.read(db)

    # Count objects
    objects = structure["objects"]
    triggers = objects.select { |o| o[0] == "trigger" }
    indexes = objects.select { |o| o[0] == "index" }
    tables = objects.select { |o| o[0] == "table" }

    # Detailed inspections
    # Check constraints and SQL inspection
    tables_with_checks = tables.select { |t| t[3] =~ /CHECK/i }.map { |t| t[1] }
    partial_indexes = indexes.select { |i| i[3] =~ /WHERE/i }.map { |i| i[1] }
    composite_fks = structure["foreign_keys"].select { |_tbl, fks| fks.any? { |fk| fk.size > 1 } }.keys

    # Logging comments inspection
    tagged_objects = objects.select { |o| o[3]&.include?("/*application='AccioHub'*/") }
    tagged_summary = tagged_objects.map { |o| { type: o[0], name: o[1], sql: o[3] } }

    # Hypothetical in-memory stripping of exact tag
    cleaned_objects = objects.map do |row|
      clean_row = row.dup
      if clean_row[3]&.end_with?(" /*application='AccioHub'*/")
        clean_row[3] = clean_row[3].delete_suffix(" /*application='AccioHub'*/")
      end
      clean_row
    end
    cleaned_structure = structure.merge("objects" => cleaned_objects)
    cleaned_fingerprint = SqliteBackupSnapshot.fingerprint(cleaned_structure)

    # 2. Backup attempt using SyntheticSqliteBackup with environment: "test"
    tool = SyntheticSqliteBackup.new(
      fixture: fixture_path,
      database: db_path,
      environment: "test",
      checkout: File.dirname(rails_root)
    )

    backup_dest = File.join(sub_dir, "backup.tar")
    backup_result = nil
    error_message = nil
    begin
      tool.backup(destination: backup_dest)
      backup_result = "accepted"
    rescue SyntheticSqliteBackup::Invalid => e
      backup_result = "rejected"
      error_message = e.message
    end

    # Confirm source database was not changed
    snapshot_after = SqliteBackupSnapshot.read(db)
    source_unchanged = (snapshot_before == snapshot_after)

    db.close

    item_data = {
      environment: env_name,
      preparation: prep_task,
      database_path: db_path,
      integrity: integrity,
      foreign_key_violations_count: fk_violations.size,
      foreign_key_violations: fk_violations,
      migrations: migrations,
      migrations_match_contract: (migrations == contract["migrations"]),
      migrations_sha256: snapshot_before["tables"]["schema_migrations"]["sha256"],
      migrations_sha256_match: (snapshot_before["tables"]["schema_migrations"]["sha256"] == contract["migrations_sha256"]),
      tables_count: tables.size,
      triggers_count: triggers.size,
      indexes_count: indexes.size,
      tables_with_checks: tables_with_checks,
      partial_indexes: partial_indexes,
      composite_fks_tables: composite_fks,
      tagged_objects_count: tagged_objects.size,
      tagged_objects: tagged_summary.map { |t| "#{t[:type]} #{t[:name]}" },
      literal_fingerprint: literal_fingerprint,
      contract_includes_literal: contract["schema_sha256"].include?(literal_fingerprint),
      cleaned_fingerprint: cleaned_fingerprint,
      contract_includes_cleaned: contract["schema_sha256"].include?(cleaned_fingerprint),
      backup_result: backup_result,
      error_message: error_message,
      source_unchanged: source_unchanged
    }

    puts "Matrix [#{idx+1}/4] #{env_name} + #{prep_task}:"
    puts "  Fingerprint: #{literal_fingerprint}"
    puts "  Contract includes literal: #{item_data[:contract_includes_literal]}"
    puts "  Tagged objects count: #{tagged_objects.size}"
    puts "  Backup result: #{backup_result} (#{error_message})"
    puts "  Cleaned fingerprint: #{cleaned_fingerprint} (in contract: #{item_data[:contract_includes_cleaned]})"
    puts "  Source unchanged: #{source_unchanged}"

    matrix_results << item_data
  end
end

output_json = File.join(output_dir, "matrix_results.json")
File.write(output_json, JSON.pretty_generate(matrix_results) + "\n")
puts "Matrix results saved to: #{output_json}"
