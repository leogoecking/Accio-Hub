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

puts "=== RUNNING ADVERSARIAL TESTS ON PROPOSED STRATEGIES ==="

# We test two strategies:
# Strategy A (Whitelist):
# Contract whitelist includes:
#   - original contract hashes: 621ee16d... and c8752c5a...
#   - development hash: b42e0bb59d064152d690856959275801ae4f1e034e291765d56bbc1874986470
strategy_a_whitelist = contract["schema_sha256"] + ["b42e0bb59d064152d690856959275801ae4f1e034e291765d56bbc1874986470"]

def evaluate_strategy_a(snapshot, contract, whitelist)
  objects = snapshot.fetch("schema").fetch("objects")
  whitelist.include?(snapshot.fetch("schema_sha256")) &&
    snapshot.fetch("tables").fetch("schema_migrations").fetch("sha256") == contract.fetch("migrations_sha256") &&
    objects.count { |row| row[0] == "trigger" } == 25 &&
    objects.count { |row| row[0] == "index" } == 36
end

# Strategy B (Strictly Delimited Normalization):
# Strips strictly the suffix " /*application='AccioHub'*/" if present on index/trigger/table objects,
# then checks against the original contract hashes.
def normalize_strictly(structure)
  cleaned_objects = structure.fetch("objects").map do |row|
    clean_row = row.dup
    if clean_row[3]&.end_with?(" /*application='AccioHub'*/")
      clean_row[3] = clean_row[3].delete_suffix(" /*application='AccioHub'*/")
    end
    clean_row
  end
  structure.merge("objects" => cleaned_objects)
end

def evaluate_strategy_b(snapshot, contract)
  objects = snapshot.fetch("schema").fetch("objects")
  normalized_struct = normalize_strictly(snapshot.fetch("schema"))
  fp = SqliteBackupSnapshot.fingerprint(normalized_struct)
  contract.fetch("schema_sha256").include?(fp) &&
    snapshot.fetch("tables").fetch("schema_migrations").fetch("sha256") == contract.fetch("migrations_sha256") &&
    objects.count { |row| row[0] == "trigger" } == 25 &&
    objects.count { |row| row[0] == "index" } == 36
end

# Base database generator (clean test database with db:schema:load)
adversarial_cases = []

Dir.mktmpdir("accio-f5-adv-") do |dir|
  base_db = File.join(dir, "base.sqlite3")
  Open3.capture3({ "RAILS_ENV" => "test", "ACCIO_DATABASE_PATH" => base_db, "SECRET_KEY_BASE" => SecureRandom.hex(64) }, "bin/rails", "db:schema:load", chdir: rails_root)

  scenarios = [
    {
      name: "1. Tampered CHECK constraint on dock_shortcuts",
      mutation: lambda do |db|
        # Recreate dock_shortcuts with weakened CHECK constraint (allow invalid module_key)
        db.execute("PRAGMA writable_schema = ON")
        sql = db.get_first_value("SELECT sql FROM sqlite_master WHERE type='table' AND name='dock_shortcuts'")
        tampered_sql = sql.sub("module_key IN ('tasks'", "module_key IN ('tampered_app','tasks'")
        db.execute("UPDATE sqlite_master SET sql=? WHERE type='table' AND name='dock_shortcuts'", [tampered_sql])
        db.execute("PRAGMA writable_schema = OFF")
      end
    },
    {
      name: "2. Tampered Foreign Key (focus_commands points to dummy)",
      mutation: lambda do |db|
        db.execute("PRAGMA writable_schema = ON")
        sql = db.get_first_value("SELECT sql FROM sqlite_master WHERE type='table' AND name='focus_commands'")
        tampered_sql = sql.sub('REFERENCES "users"', 'REFERENCES "tampered_users"')
        db.execute("UPDATE sqlite_master SET sql=? WHERE type='table' AND name='focus_commands'", [tampered_sql])
        db.execute("PRAGMA writable_schema = OFF")
      end
    },
    {
      name: "3. Tampered Index (change indexed column)",
      mutation: lambda do |db|
        db.execute("PRAGMA writable_schema = ON")
        sql = db.get_first_value("SELECT sql FROM sqlite_master WHERE type='index' AND name='index_auth_sessions_on_user_id'")
        tampered_sql = sql.sub('("user_id")', '("expires_at")')
        db.execute("UPDATE sqlite_master SET sql=? WHERE type='index' AND name='index_auth_sessions_on_user_id'", [tampered_sql])
        db.execute("PRAGMA writable_schema = OFF")
      end
    },
    {
      name: "4. Tampered Partial Index (remove WHERE clause)",
      mutation: lambda do |db|
        db.execute("PRAGMA writable_schema = ON")
        sql = db.get_first_value("SELECT sql FROM sqlite_master WHERE type='index' AND name='widget_home_key'")
        tampered_sql = sql.sub(" WHERE context = 'home'", "")
        db.execute("UPDATE sqlite_master SET sql=? WHERE type='index' AND name='widget_home_key'", [tampered_sql])
        db.execute("PRAGMA writable_schema = OFF")
      end
    },
    {
      name: "5. Tampered Trigger (modify trigger action/message)",
      mutation: lambda do |db|
        db.execute("PRAGMA writable_schema = ON")
        sql = db.get_first_value("SELECT sql FROM sqlite_master WHERE type='trigger' AND name='accio_focus_delete'")
        tampered_sql = sql.sub("Tentativas de foco são preservadas", "Tentativas de foco podem ser deletadas")
        db.execute("UPDATE sqlite_master SET sql=? WHERE type='trigger' AND name='accio_focus_delete'", [tampered_sql])
        db.execute("PRAGMA writable_schema = OFF")
      end
    },
    {
      name: "6. Tampered Column Type (change INTEGER to TEXT)",
      mutation: lambda do |db|
        db.execute("PRAGMA writable_schema = ON")
        sql = db.get_first_value("SELECT sql FROM sqlite_master WHERE type='table' AND name='projects'")
        tampered_sql = sql.sub('"lock_version" integer', '"lock_version" text')
        db.execute("UPDATE sqlite_master SET sql=? WHERE type='table' AND name='projects'", [tampered_sql])
        db.execute("PRAGMA writable_schema = OFF")
      end
    },
    {
      name: "7. Tampered Table Name (ALTER TABLE projects RENAME TO hacked_projects)",
      mutation: lambda do |db|
        db.execute('ALTER TABLE projects RENAME TO hacked_projects')
      end
    },
    {
      name: "8. Malicious Arbitrary SQL Comment in Index DDL",
      mutation: lambda do |db|
        db.execute("PRAGMA writable_schema = ON")
        sql = db.get_first_value("SELECT sql FROM sqlite_master WHERE type='index' AND name='index_users_on_email_address'")
        tampered_sql = sql + " /* malicious payload comment */"
        db.execute("UPDATE sqlite_master SET sql=? WHERE type='index' AND name='index_users_on_email_address'", [tampered_sql])
        db.execute("PRAGMA writable_schema = OFF")
      end
    },
    {
      name: "9. Deceptive Tag (different application name: AccioMalicious)",
      mutation: lambda do |db|
        db.execute("PRAGMA writable_schema = ON")
        sql = db.get_first_value("SELECT sql FROM sqlite_master WHERE type='index' AND name='index_users_on_email_address'")
        tampered_sql = sql + " /*application='AccioMalicious'*/"
        db.execute("UPDATE sqlite_master SET sql=? WHERE type='index' AND name='index_users_on_email_address'", [tampered_sql])
        db.execute("PRAGMA writable_schema = OFF")
      end
    },
    {
      name: "10. Injected Tag inside middle of query rather than suffix",
      mutation: lambda do |db|
        db.execute("PRAGMA writable_schema = ON")
        sql = db.get_first_value("SELECT sql FROM sqlite_master WHERE type='index' AND name='index_users_on_email_address'")
        tampered_sql = sql.sub('ON "users"', "/*application='AccioHub'*/ ON \"users\"")
        db.execute("UPDATE sqlite_master SET sql=? WHERE type='index' AND name='index_users_on_email_address'", [tampered_sql])
        db.execute("PRAGMA writable_schema = OFF")
      end
    },
    {
      name: "11. Altered schema_migrations row (delete a migration)",
      mutation: lambda do |db|
        db.execute("DELETE FROM schema_migrations WHERE version='20261012040000'")
      end
    }
  ]

  scenarios.each_with_index do |sc, idx|
    sub = File.join(dir, "sc_#{idx+1}")
    Dir.mkdir(sub, 0o700)
    db_copy = File.join(sub, "synthetic.sqlite3")
    FileUtils.cp(base_db, db_copy)
    File.chmod(0o600, db_copy)

    db = SQLite3::Database.new(db_copy)
    sc[:mutation].call(db)
    db.close

    # Reopen to read snapshot
    db_ro = SQLite3::Database.new(db_copy, readonly: true)
    snapshot = nil
    read_error = nil
    begin
      snapshot = SqliteBackupSnapshot.read(db_ro)
    rescue SQLite3::Exception => e
      read_error = e.message
    ensure
      db_ro.close
    end

    strategy_a_accepted = false
    strategy_b_accepted = false
    if snapshot
      strategy_a_accepted = evaluate_strategy_a(snapshot, contract, strategy_a_whitelist)
      strategy_b_accepted = evaluate_strategy_b(snapshot, contract)
    end

    # Also test actual SyntheticSqliteBackup behavior against these
    fixture_path = File.join(sub, "fixture.json")
    File.write(fixture_path, JSON.generate({ format: "accio-f3a-synthetic", version: 1, database: "synthetic.sqlite3" }), perm: 0o600)

    tool = SyntheticSqliteBackup.new(fixture: fixture_path, database: db_copy, environment: "test", checkout: File.dirname(rails_root))
    actual_backup_result = nil
    actual_backup_error = nil
    begin
      tool.backup(destination: File.join(sub, "backup.tar"))
      actual_backup_result = "accepted"
    rescue SyntheticSqliteBackup::Invalid => e
      actual_backup_result = "rejected"
      actual_backup_error = e.message
    rescue SQLite3::Exception => e
      actual_backup_result = "rejected (sqlite error)"
      actual_backup_error = e.message
    end

    res = {
      scenario: sc[:name],
      strategy_a_rejected: (!strategy_a_accepted),
      strategy_b_rejected: (!strategy_b_accepted),
      current_tool_rejected: (actual_backup_result == "rejected"),
      actual_backup_error: actual_backup_error
    }

    puts "Adversarial [#{idx+1}/#{scenarios.size}] #{sc[:name]}:"
    puts "  Strategy A rejected: #{res[:strategy_a_rejected]}"
    puts "  Strategy B rejected: #{res[:strategy_b_rejected]}"
    puts "  Current Tool rejected: #{res[:current_tool_rejected]} (#{actual_backup_error})"

    adversarial_cases << res
  end
end

output_adv = File.join(output_dir, "adversarial_results.json")
File.write(output_adv, JSON.pretty_generate(adversarial_cases) + "\n")
puts "Adversarial results saved to: #{output_adv}"
