require "test_helper"
require "tmpdir"
require "open3"
require "fileutils"

class SqliteBackupContractTest < ActiveSupport::TestCase
  DEVELOPMENT = %w[edc335eb6c71b2062b5a65c4563fcbe0fe341deaa5ca55ac7383f8dd92ec5751 b42e0bb59d064152d690856959275801ae4f1e034e291765d56bbc1874986470].freeze
  ORIGINALS = %w[621ee16d32be40ae482a50c92cc8a3fc55fc92d5aa27186e34506e1b77f529e8 c8752c5aabda1b9064750d8982648e89eaacfb4d68d117f36c3ad1e77ca542f7].freeze

  setup do
    @directory = Dir.mktmpdir("accio-f501-unit-")
    @database = File.join(@directory, "synthetic.sqlite3")
    @fixture = File.join(@directory, "fixture.json")
    File.write(@fixture, JSON.generate({ format: "accio-f3a-synthetic", version: 1, database: "synthetic.sqlite3" }), perm: 0o600)
  end

  teardown do
    FileUtils.remove_entry(@directory)
  end

  def prepare(creation = "test", task = "db:schema:load")
    environment = { "RAILS_ENV" => creation, "ACCIO_DATABASE_PATH" => @database,
      "SECRET_KEY_BASE" => SecureRandom.hex(64) }
    environment["SCHEMA"] = File.join(@directory, "generated-schema.rb") if task == "db:migrate"
    _, error, status = Open3.capture3(environment, "bin/rails", task, chdir: Rails.root)
    assert status.success?, error.lines.first
    File.chmod(0o600, @database)
  end

  def snapshot
    db = SQLite3::Database.new(@database, readonly: true)
    db.execute("BEGIN")
    SqliteBackupSnapshot.read(db)
  ensure
    db&.close
  end

  def tool
    SyntheticSqliteBackup.new(fixture: @fixture, database: @database, environment: "test", checkout: Rails.root.parent.to_s)
  end

  def mutate_sql(name)
    db = SQLite3::Database.new(@database)
    original = db.get_first_value("SELECT sql FROM sqlite_master WHERE name=?", [ name ])
    replacement = yield original
    assert_not_equal original, replacement
    db.execute("PRAGMA writable_schema=ON")
    db.execute("UPDATE sqlite_master SET sql=? WHERE name=?", [ replacement, name ])
    db.execute("PRAGMA writable_schema=OFF")
    db.execute("PRAGMA schema_version=#{db.get_first_value('PRAGMA schema_version') + 1}")
  ensure
    db&.close
  end

  test "contract preserves original fields and adds only the explicit development fingerprint" do
    contract = JSON.parse(File.read(Rails.root.join("config/sqlite_backup_contract.json")))
    assert_equal %w[format version schema_sha256 migrations migrations_sha256], contract.keys
    assert_equal "accio-sqlite-schema-contract", contract.fetch("format")
    assert_equal 1, contract.fetch("version")
    assert_equal ORIGINALS + DEVELOPMENT, contract.fetch("schema_sha256")
    assert_equal %w[20261011010000 20261012010000 20261012020000 20261012030000 20261012040000], contract.fetch("migrations")
    assert_equal "07cf9e1c10867429a2242b9d683b8554bc185f4de1030605e1aeebe9a94e7993", contract.fetch("migrations_sha256")
  end

  %w[test development].product(%w[db:migrate db:schema:load]).each do |creation, preparation|
    test "#{creation} #{preparation} backs up verbatim with a test-only administrative tool" do
      prepare(creation, preparation)
      before = snapshot
      expected = creation == "test" ? ORIGINALS : DEVELOPMENT
      assert_equal expected[preparation == "db:migrate" ? 0 : 1], before.fetch("schema_sha256")
      archive = File.join(@directory, "development.tar")
      result = tool.backup(destination: archive)
      assert_equal true, result["verified"]
      assert_equal 25, result["triggers"]
      assert_equal 36, result["indexes"]
      assert_equal result, tool.verify(archive)
      assert_equal before, snapshot
      record_result({ type: "positive", creation: creation, preparation: preparation, schema_sha256: before.fetch("schema_sha256"), verified: true, source_unchanged: true })
      assert_raises(SyntheticSqliteBackup::Invalid) do
        SyntheticSqliteBackup.new(fixture: @fixture, database: @database, environment: "development", checkout: Rails.root.parent.to_s)
      end
    end
  end

  %w[unknown_schema check foreign_key index partial_index trigger column_type renamed_table arbitrary_comment forged_tag migrations unlisted_fingerprint].each do |mutation|
    test "rejects #{mutation} without publishing or changing the mutated synthetic source" do
      prepare
      case mutation
      when "unknown_schema"
        db = SQLite3::Database.new(@database)
        db.execute("CREATE TABLE unknown_f501 (id INTEGER)")
        db.close
      when "check"
        mutate_sql("dock_shortcuts") { |sql| sql.sub("position >= 0", "position >= 1") }
      when "foreign_key"
        mutate_sql("auth_sessions") { |sql| sql.sub('REFERENCES "users" ("id")', 'REFERENCES "projects" ("id")') }
      when "index"
        mutate_sql("index_users_on_email_address") { |sql| sql.sub('("email_address")', '("id")') }
      when "partial_index"
        mutate_sql("one_global_focus") { |sql| sql.sub(/WHERE .*/m, "WHERE status = 'running'") }
      when "trigger"
        mutate_sql("accio_focus_delete") { |sql| sql.sub("RAISE(ABORT", "RAISE(FAIL") }
      when "column_type"
        mutate_sql("projects") { |sql| sql.sub(/("lock_version"\s+)integer/i, '\1text') }
      when "renamed_table"
        db = SQLite3::Database.new(@database)
        db.execute("ALTER TABLE project_references RENAME TO renamed_f501")
        db.close
      when "arbitrary_comment"
        mutate_sql("index_users_on_email_address") { |sql| sql + " /*unknown-comment*/" }
      when "forged_tag"
        mutate_sql("index_users_on_email_address") { |sql| sql + " /*application='AccioOther'*/" }
      when "migrations"
        db = SQLite3::Database.new(@database)
        db.execute("DELETE FROM schema_migrations WHERE version=(SELECT min(version) FROM schema_migrations)")
        db.close
      when "unlisted_fingerprint"
        mutate_sql("index_users_on_email_address") { |sql| sql.sub(/\ACREATE /, "CREATE  ") }
      end
      before = snapshot
      db = SQLite3::Database.new(@database, readonly: true)
      assert_equal "ok", db.get_first_value("PRAGMA integrity_check")
      assert_empty db.execute("PRAGMA foreign_key_check")
      db.close
      archive = File.join(@directory, "refused.tar")
      error = assert_raises(SyntheticSqliteBackup::Invalid) { tool.backup(destination: archive) }
      assert_equal "Schema incompatível com esta versão da aplicação", error.message
      assert_not File.exist?(archive)
      assert_equal before, snapshot
      record_result({ type: "negative", mutation: mutation, schema_sha256: before.fetch("schema_sha256"), refused: true, no_artifact: true, source_unchanged: true })
    end
  end

  def record_result(row)
    path = ENV["ACCIO_F501_TEST_EVIDENCE"]
    File.open(path, "a", 0o600) { |file| file.puts(JSON.generate(row)) } if path
  end
end
