#!/usr/bin/env ruby
require "bundler/setup"
require "tmpdir"
require "open3"
require "json"
require "fileutils"

root = File.expand_path("..", __dir__)
evidence = File.expand_path(ENV.fetch("ACCIO_QA_EVIDENCE"))
FileUtils.mkdir_p(evidence)
Dir.mktmpdir("f2b-sql-", File.join(root, "tmp")) do |directory|
  env = { "RAILS_ENV" => "test", "ACCIO_DATABASE_PATH" => File.join(directory, "migrated.sqlite3") }
  run = lambda do |args, changes = {}|
    output, error, status = Open3.capture3(env.merge(changes), *args, chdir: root)
    raise "Synthetic SQL check failed: #{error}\n#{output}" unless status.success?
    output
  end
  runner = File.join(directory, "inspect.rb")
  File.write(runner, <<~'CODE')
    require "json"
    c = ActiveRecord::Base.connection
    raise "Not a new synthetic F2b database" unless c.pool.db_config.database.include?("/tmp/f2b-sql-")
    objects = c.select_all("SELECT type,name,tbl_name,sql FROM sqlite_master WHERE type IN ('trigger','index') ORDER BY type,name").to_a
    fks = c.tables.sort.to_h { |table| [ table, c.select_all("PRAGMA foreign_key_list(#{c.quote_table_name(table)})").to_a ] }
    checks = { integrity: c.select_value("PRAGMA integrity_check"), foreign_key_violations: c.select_all("PRAGMA foreign_key_check").to_a,
      foreign_keys: c.select_value("PRAGMA foreign_keys"), journal_mode: c.select_value("PRAGMA journal_mode"), synchronous: c.select_value("PRAGMA synchronous"), ignore_check_constraints: c.select_value("PRAGMA ignore_check_constraints") }
    raise "SQLite pragmas unsafe" unless checks == { integrity: "ok", foreign_key_violations: [], foreign_keys: 1, journal_mode: "wal", synchronous: 2, ignore_check_constraints: 0 }
    raise "Wrong trigger/index count" unless objects.count { |r| r["type"] == "trigger" } == 25 && objects.count { |r| r["type"] == "index" } == 36
    puts JSON.generate({ objects: objects, foreign_keys: fks, checks: checks })
  CODE
  migrated_log = run.call([ "bin/rails", "db:migrate" ], "SCHEMA" => File.join(directory, "generated-schema.rb"))
  File.write(File.join(evidence, "migrate.log"), migrated_log.rstrip + "\n")
  migrated = JSON.parse(run.call([ "bin/rails", "runner", runner ]))
  loaded_env = { "ACCIO_DATABASE_PATH" => File.join(directory, "loaded.sqlite3") }
  File.write(File.join(evidence, "schema-load.log"), run.call([ "bin/rails", "db:schema:load" ], loaded_env).rstrip + "\n")
  loaded = JSON.parse(run.call([ "bin/rails", "runner", runner ], loaded_env))
  File.write(File.join(evidence, "migrated.json"), JSON.pretty_generate(migrated) + "\n")
  File.write(File.join(evidence, "schema-loaded.json"), JSON.pretty_generate(loaded) + "\n")
  canonical_fks = lambda do |tables|
    tables.transform_values do |rows|
      rows.group_by { |row| row.fetch("id") }.values.map do |group|
        group.sort_by { |row| row.fetch("seq") }.map { |row| row.except("id") }
      end.sort_by { |group| JSON.generate(group) }
    end
  end
  raise "Trigger/index SQL differs" unless migrated.fetch("objects") == loaded.fetch("objects")
  raise "Foreign key definitions differ" unless canonical_fks.call(migrated.fetch("foreign_keys")) == canonical_fks.call(loaded.fetch("foreign_keys"))
  raise "SQLite checks differ" unless migrated.fetch("checks") == loaded.fetch("checks")
  # Existing adversarial SQL/transaction tests run independently against both preparations.
  %w[migrated loaded].each do |mode|
    db = File.join(directory, "#{mode}.sqlite3")
    tests = run.call([ "bin/rails", "test", "test/models/relational_sql_test.rb", "test/models/relational_transactions_test.rb", "test/services/focus_sql_compatibility_test.rb", "test/models/transversal_identity_test.rb" ], "ACCIO_DATABASE_PATH" => db)
    File.write(File.join(evidence, "#{mode}-tests.log"), tests.rstrip + "\n")
  end
  File.write(File.join(evidence, "comparison.json"), JSON.pretty_generate({ exact_objects_sql_and_semantic_fk_and_pragmas_match: true, fk_internal_id_order_differs: true, triggers: 25, indexes: 36, independent_migrations_and_schema_load: true, integrity: "ok" }) + "\n")
  puts "Two new synthetic databases: migrations/schema identical; 25 triggers, 36 indexes, FKs, WAL/FULL and SQL tests approved."
end
