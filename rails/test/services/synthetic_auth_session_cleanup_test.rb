require "test_helper"
require "tmpdir"
require "open3"
require "fileutils"
require "minitest/mock"

class SyntheticAuthSessionCleanupTest < ActiveSupport::TestCase
  setup do
    @directory = Dir.mktmpdir("accio-f3c-unit-")
    @database = File.join(@directory, "synthetic.sqlite3")
    @fixture = File.join(@directory, "fixture.json")
    File.write(@fixture, JSON.generate({ format: "accio-f3a-synthetic", version: 1, database: "synthetic.sqlite3" }), perm: 0o600)
    _, error, status = Open3.capture3({ "RAILS_ENV" => "test", "ACCIO_DATABASE_PATH" => @database }, "bin/rails", "db:schema:load", chdir: Rails.root)
    assert status.success?, "Synthetic schema unavailable: #{error.lines.first}"
    File.chmod(0o600, @database)
    @db = SQLite3::Database.new(@database)
    @db.execute("PRAGMA foreign_keys=ON")
    @db.execute("PRAGMA journal_mode=WAL")
    @db.execute("INSERT INTO users(id,email_address,password_digest,created_at,updated_at) VALUES(1,'fixture@example.test','synthetic-non-login-digest','2026-01-01','2026-01-01')")
    @cutoff = Time.utc(2026, 10, 22, 12, 0, 0, 123456)
  end

  teardown do
    @db&.close
    FileUtils.remove_entry(@directory)
  end

  def tool(**options)
    SyntheticAuthSessionCleanup.new(**{ fixture: @fixture, database: @database, environment: "test", checkout: Rails.root.parent.to_s, clock: -> { @cutoff } }.merge(options))
  end

  def add_session(expiration, owner = 1)
    raw = expiration.is_a?(Time) ? expiration.utc.strftime("%Y-%m-%d %H:%M:%S.%6N") : expiration
    @db.execute("INSERT INTO auth_sessions(user_id,expires_at,created_at,updated_at) VALUES(?,?,?,?)", [ owner, raw, "2026-01-01 00:00:00", "2026-01-01 00:00:00" ])
    @db.last_insert_row_id
  end

  def snapshot
    SqliteBackupSnapshot.read(@db)
  end

  def clean(&block)
    tool.cleanup(confirmation: SyntheticAuthSessionCleanup::CONFIRMATION, &block)
  end

  test "dry run repeated is read only and boundary uses existing expires at policy" do
    add_session(@cutoff - Rational(1, 1_000_000))
    add_session(@cutoff)
    active = add_session(@cutoff + Rational(1, 1_000_000))
    before = snapshot
    2.times do
      result = tool.inventory
      assert_equal 2, result["expired"]
      assert_equal 1, result["active"]
      assert_equal 0, result["deleted"]
      assert_equal false, result["committed"]
      assert_equal before, snapshot
    end
    result = clean
    assert_equal 2, result["deleted"]
    assert_equal [ [ active ] ], @db.execute("SELECT id FROM auth_sessions")
    assert_equal before["tables"].except("auth_sessions"), snapshot["tables"].except("auth_sessions")
    assert_equal 0, clean["deleted"]
  end

  test "unclassifiable expiry is preserved without coercion and created or updated dates do not decide" do
    malformed = [ "2026-02-30 12:00:00", "2026-01-01 24:00:00", "2026-01-01 00:00:60", "2020-01-01", "", "not-a-date", 42, SQLite3::Blob.new("2020-01-01 00:00:00"), "2020-01-01T00:00:00Z", "2020-01-01 00:00:00.0000000" ]
    malformed.each { |raw| add_session(raw) }
    active = add_session(@cutoff + 10)
    @db.execute("UPDATE auth_sessions SET created_at='1900-01-01',updated_at='1900-01-01' WHERE id=?", [ active ])
    add_session("2020-01-01 00:00:00")
    result = clean
    assert_equal malformed.size, result["unclassified_preserved"]
    assert_equal 1, result["deleted"]
    assert_equal malformed.size + 1, @db.get_first_value("SELECT count(*) FROM auth_sessions")
  end

  test "empty active only expired only and paged sets remain consistent" do
    assert_equal 0, clean["deleted"]
    add_session(@cutoff + 1)
    assert_equal 0, clean["deleted"]
    @db.execute("DELETE FROM auth_sessions")
    205.times { add_session(@cutoff - 1) }
    assert_equal 205, clean["deleted"]
    assert_equal 0, @db.get_first_value("SELECT count(*) FROM auth_sessions")
  end

  test "no or incorrect confirmation refuses deletion" do
    add_session(@cutoff - 1)
    before = snapshot
    [ nil, "", true, "delete", "DELETE_EXPIRED_AUTH_SESSIONS " ].each do |value|
      assert_raises(SyntheticAuthSessionCleanup::Invalid) { tool.cleanup(confirmation: value) }
      assert_equal before, snapshot
    end
  end

  test "existing SQL singleton and foreign key prohibit other owners without relaxing schema" do
    assert_raises(SQLite3::ConstraintException) do
      @db.execute("INSERT INTO users(id,email_address,password_digest,created_at,updated_at) VALUES(2,'other@example.test','synthetic-other','2026-01-01','2026-01-01')")
    end
    assert_raises(SQLite3::ConstraintException) { add_session(@cutoff - 10, 2) }
    add_session(@cutoff - 10)
    assert_equal 1, clean["deleted"]
    assert_equal [], @db.execute("SELECT id,user_id FROM auth_sessions")
  end

  test "single cutoff and rollback includes earlier pages" do
    205.times { add_session(@cutoff - 1) }
    active = add_session(@cutoff + 1)
    before = snapshot
    calls = 0
    selected = tool(clock: -> { calls += 1; @cutoff })
    pages = 0
    assert_raises(IOError) do
      selected.cleanup(confirmation: SyntheticAuthSessionCleanup::CONFIRMATION) do |stage|
        next unless stage == :page_processed
        pages += 1
        raise IOError, "Synthetic late failure" if pages == 2
      end
    end
    assert_equal 1, calls
    assert_equal 2, pages
    assert_equal before, snapshot
    assert_equal 205, clean["deleted"]
    assert_equal [ [ active ] ], @db.execute("SELECT id FROM auth_sessions")
  end

  test "new tool after process restart sees successful cleanup and never deletes future sessions" do
    add_session(@cutoff - 1)
    active = add_session(@cutoff + 1)
    assert_equal 1, clean["deleted"]
    result = tool.inventory
    assert_equal 0, result["expired"]
    assert_equal 1, result["active"]
    assert_equal [ [ active ] ], @db.execute("SELECT id FROM auth_sessions")
  end

  test "environment fixture absent paths default and missing database are refused before opening" do
    before = snapshot
    missing = File.join(@directory, "missing.sqlite3")
    [ { environment: "development" }, { environment: "production" }, { environment: nil }, { database: nil }, { fixture: nil },
      { database: missing }, { fixture: File.join(@directory, "absent.json") } ].each do |options|
      assert_raises(SyntheticAuthSessionCleanup::Invalid) { tool(**options) }
      assert_not File.exist?(missing)
    end
    assert_equal before, snapshot
  end

  test "public paths links unsafe permissions and incompatible fixture refused" do
    File.chmod(0o644, @database)
    assert_raises(SyntheticAuthSessionCleanup::Invalid) { tool }
    File.chmod(0o600, @database)
    File.chmod(0o755, @directory)
    assert_raises(SyntheticAuthSessionCleanup::Invalid) { tool }
    File.chmod(0o700, @directory)
    File.write(@fixture, JSON.generate({ format: "not-synthetic" }))
    assert_raises(SyntheticAuthSessionCleanup::Invalid) { tool }
    File.delete(@fixture)
    File.symlink(@database, @fixture)
    assert_raises(SyntheticAuthSessionCleanup::Invalid) { tool }
  end

  test "revalidation refuses disappeared source without recreating it" do
    selected = tool
    @db.close
    @db = nil
    File.delete(@database)
    assert_raises(SyntheticAuthSessionCleanup::Invalid) { selected.inventory }
    assert_not File.exist?(@database)
  end

  test "missing administrator incompatible schema corruption and read failure refuse writes" do
    @db.execute("DELETE FROM users")
    assert_raises(SyntheticAuthSessionCleanup::Invalid) { clean }
    @db.execute("CREATE TABLE incompatible(value TEXT)")
    assert_raises(SyntheticAuthSessionCleanup::Invalid) { tool.inventory }
    @db.close
    @db = nil
    File.binwrite(@database, "not a database")
    assert_raises(SyntheticAuthSessionCleanup::Invalid) { tool.inventory }
  end

  test "backup verification remains possible after ordinary cleanup without modifying backup services" do
    add_session(@cutoff - 1)
    add_session(@cutoff + 1)
    clean
    before = snapshot
    archive = File.join(@directory, "after-cleanup.tar")
    backup = SyntheticSqliteBackup.new(fixture: @fixture, database: @database, environment: "test", checkout: Rails.root.parent.to_s)
    result = backup.backup(destination: archive)
    assert_equal 1, result["tables"]["auth_sessions"]
    assert_equal result, backup.verify(archive)
    assert_equal before, snapshot
  end

  test "unreadable file and read only database fail safely" do
    selected = tool
    File.chmod(0o000, @database)
    assert_raises(SyntheticAuthSessionCleanup::Invalid) { selected.inventory }
    File.chmod(0o400, @database)
    assert_raises(SyntheticAuthSessionCleanup::Invalid) { selected.cleanup(confirmation: SyntheticAuthSessionCleanup::CONFIRMATION) }
    File.chmod(0o600, @database)
  end

  test "unusual legal SQL identifiers are scanned and public metadata has no private values" do
    @db.execute("INSERT INTO auth_sessions(id,user_id,expires_at,created_at,updated_at) VALUES(-1,1,'2020-01-01 00:00:00','2020-01-01','2020-01-01')")
    @db.execute("INSERT INTO auth_sessions(id,user_id,expires_at,created_at,updated_at) VALUES(0,1,'2020-01-01 00:00:00','2020-01-01','2020-01-01')")
    add_session(@cutoff + 1)
    result = tool.inventory
    assert_equal 3, result["scanned"]
    assert_equal 2, result["expired"]
    assert_equal %w[mode cutoff_utc scanned expired active unclassified_preserved deleted committed].sort, result.keys.sort
    assert_not_includes JSON.generate(result), "fixture@example.test"
    assert_not_includes JSON.generate(result), "synthetic-non-login-digest"
    assert_equal 2, clean["deleted"]
  end

  test "renewed session is reclassified from the transaction snapshot rather than old inventory" do
    id = add_session(@cutoff - 1)
    assert_equal 1, tool.inventory["expired"]
    @db.execute("UPDATE auth_sessions SET expires_at=? WHERE id=?", [ (@cutoff + 10).strftime("%Y-%m-%d %H:%M:%S.%6N"), id ])
    before = snapshot
    assert_equal 0, clean["deleted"]
    assert_equal before, snapshot
  end

  test "source symlink and unreadable fixture are refused without opening another database" do
    selected = tool
    File.chmod(0o000, @fixture)
    assert_raises(SyntheticAuthSessionCleanup::Invalid) { selected.inventory }
    File.chmod(0o600, @fixture)
    @db.close
    @db = nil
    moved = File.join(@directory, "other.sqlite3")
    File.rename(@database, moved)
    File.symlink(moved, @database)
    assert_raises(SyntheticAuthSessionCleanup::Invalid) { selected.cleanup(confirmation: SyntheticAuthSessionCleanup::CONFIRMATION) }
    SQLite3::Database.new(moved, readonly: true) do |connection|
      assert_equal 0, connection.get_first_value("SELECT count(*) FROM auth_sessions")
    end
  end
end
