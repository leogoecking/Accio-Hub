require "test_helper"
require "tmpdir"
require "open3"
require "fileutils"
require "minitest/mock"
require "timeout"

class SyntheticSqliteBackupTest < ActiveSupport::TestCase
  setup do
    @directory = Dir.mktmpdir("accio-f3b-unit-")
    @database = File.join(@directory, "synthetic.sqlite3")
    @fixture = File.join(@directory, "fixture.json")
    File.write(@fixture, JSON.generate({ format: "accio-f3a-synthetic", version: 1, database: "synthetic.sqlite3" }), perm: 0o600)
    output, error, status = Open3.capture3({ "RAILS_ENV" => "test", "ACCIO_DATABASE_PATH" => @database }, "bin/rails", "db:schema:load", chdir: Rails.root)
    assert status.success?, "Synthetic schema failed: #{error.lines.first} #{output.lines.first}"
    File.chmod(0o600, @database)
    @db = SQLite3::Database.new(@database)
    @db.execute("PRAGMA foreign_keys=ON")
    @db.execute("PRAGMA journal_mode=WAL")
    @db.execute("PRAGMA synchronous=FULL")
    @db.execute("INSERT INTO users(id,email_address,password_digest,created_at,updated_at) VALUES (1,'fixture@example.test','synthetic-non-login-digest','2026-01-01','2026-01-01')")
    @db.execute("INSERT INTO auth_sessions(user_id,expires_at,created_at,updated_at) VALUES (1,'2099-01-01','2026-01-01','2026-01-01')")
    @db.execute("INSERT INTO auth_sessions(user_id,expires_at,created_at,updated_at) VALUES (1,'2020-01-01','2020-01-01','2020-01-01')")
    @tool = tool
    @archive = File.join(@directory, "backup.tar")
    @restored = File.join(@directory, "restored")
  end

  teardown do
    @db&.close
    FileUtils.remove_entry(@directory)
  end

  def tool(**options)
    SyntheticSqliteBackup.new(**{ fixture: @fixture, database: @database, environment: "test", checkout: Rails.root.parent.to_s }.merge(options))
  end

  def snapshot(path = @database)
    connection = SQLite3::Database.new(path, readonly: true)
    connection.execute("BEGIN")
    SqliteBackupSnapshot.read(connection)
  ensure
    connection&.close
  end

  def check_source(before)
    assert_equal before, snapshot
    assert_equal "wal", @db.get_first_value("PRAGMA journal_mode")
    assert_equal 2, @db.get_first_value("PRAGMA synchronous")
  end

  def rewrite_archive
    members = {}
    File.open(@archive, "rb") do |input|
      Gem::Package::TarReader.new(input) { |tar| tar.each { |entry| members[entry.full_name] = entry.read } }
    end
    yield members
    File.open(@archive, "wb") do |output|
      Gem::Package::TarWriter.new(output) do |tar|
        members.each { |name, bytes| tar.add_file_simple(name, 0o600, bytes.bytesize) { |entry| entry.write(bytes.b) } }
      end
    end
  end

  test "online backup preserves all data schema constraints and active WAL without source writes" do
    before = snapshot
    stages = []
    result = @tool.backup(destination: @archive) { |stage| stages << stage }
    assert result["verified"]
    assert_includes stages, :snapshot_pinned
    assert_includes stages, :backup_step
    assert_includes stages, :backup_verified
    assert_equal 25, result["triggers"]
    assert_equal 36, result["indexes"]
    assert_equal 2, result["tables"]["auth_sessions"]
    assert_equal 0o600, File.stat(@archive).mode & 0o777
    assert_equal result, @tool.verify(@archive)
    check_source(before)
  end

  test "restoration verifies fidelity then revokes only copied sessions before publication" do
    before = snapshot
    @tool.backup(destination: @archive)
    stages = []
    result = @tool.restore(archive: @archive, directory: @restored) { |stage| stages << stage }
    assert_equal true, result["prepared"]
    assert_equal 2, result["revoked_sessions"]
    assert_operator stages.index(:restore_fidelity_verified), :<, stages.index(:before_auth_revocation)
    assert_operator stages.index(:auth_sessions_revoked), :<, stages.index(:restore_prepared)
    target = snapshot(File.join(@restored, "synthetic.sqlite3"))
    assert_equal before["schema"], target["schema"]
    assert_equal before["tables"].except("auth_sessions"), target["tables"].except("auth_sessions")
    assert_equal 0, target["tables"]["auth_sessions"]["rows"]
    target_tool = tool(database: File.join(@restored, "synthetic.sqlite3"), fixture: File.join(@restored, "fixture.json"))
    secret = target_tool.runtime(directory: @restored)
    assert_match(/\A[0-9a-f]{128}\z/, secret)
    assert_not_includes File.read(File.join(@restored, "RESTORED.json")), secret
    assert_not_equal ENV["SECRET_KEY_BASE"], secret
    check_source(before)
  end

  test "source remains pinned while a different process commits during backup" do
    before = snapshot
    writer = nil
    @tool.backup(destination: @archive) do |stage|
      next unless stage == :snapshot_pinned
      writer = fork do
        connection = SQLite3::Database.new(@database)
        connection.execute("PRAGMA foreign_keys=ON")
        connection.execute("UPDATE users SET updated_at='2026-02-01' WHERE id=1")
        connection.close
        exit! 0
      end
      _, status = Process.wait2(writer)
      writer = nil
      assert status.success?
    end
    assert_not_equal before, snapshot
    @tool.restore(archive: @archive, directory: @restored)
    copied = snapshot(File.join(@restored, "synthetic.sqlite3"))
    assert_equal before["tables"]["users"], copied["tables"]["users"]
  ensure
    if writer
      Process.kill("KILL", writer)
      Process.wait(writer)
    end
  end

  test "missing defaults wrong environment public fixture and missing source are refused" do
    [ { environment: "development" }, { fixture: nil }, { database: nil } ].each do |options|
      assert_raises(SyntheticSqliteBackup::Invalid) { tool(**options) }
    end
    File.chmod(0o644, @fixture)
    assert_raises(SyntheticSqliteBackup::Invalid) { tool }
    File.chmod(0o600, @fixture)
    @db.close
    @db = nil
    File.unlink(@database)
    assert_raises(SyntheticSqliteBackup::Invalid) { tool }
    assert_not File.exist?(@database)
  end

  test "empty uninitialized database incompatible schema and corrupt source do not publish" do
    @db.execute("CREATE TABLE incompatible (id INTEGER)")
    assert_raises(SyntheticSqliteBackup::Invalid) { @tool.backup(destination: @archive) }
    assert_not File.exist?(@archive)
    @db.close
    @db = nil
    File.binwrite(@database, "")
    assert_raises(SyntheticSqliteBackup::Invalid) { @tool.backup(destination: @archive) }
    File.binwrite(@database, "not a SQLite database")
    assert_raises(SyntheticSqliteBackup::Invalid) { @tool.backup(destination: @archive) }
    assert_not File.exist?(@archive)
  end

  test "schema without application rows can be backed up without inventing an administrator" do
    @db.execute("DELETE FROM auth_sessions")
    @db.execute("DELETE FROM users")
    result = @tool.backup(destination: @archive)
    assert_equal 0, result["tables"]["users"]
    @tool.restore(archive: @archive, directory: @restored)
    assert_equal 0, snapshot(File.join(@restored, "synthetic.sqlite3"))["tables"]["users"]["rows"]
  end

  test "a new database prepared by migrations satisfies the same backup contract" do
    directory = File.join(@directory, "migrated")
    Dir.mkdir(directory, 0o700)
    database = File.join(directory, "synthetic.sqlite3")
    fixture = File.join(directory, "fixture.json")
    File.write(fixture, File.read(@fixture), perm: 0o600)
    _, _, status = Open3.capture3({ "RAILS_ENV" => "test", "ACCIO_DATABASE_PATH" => database,
      "SCHEMA" => File.join(directory, "generated-schema.rb") }, "bin/rails", "db:migrate", chdir: Rails.root)
    assert status.success?
    File.chmod(0o600, database)
    migrated = tool(database: database, fixture: fixture)
    result = migrated.backup(destination: File.join(directory, "migrated.tar"))
    assert_equal 25, result["triggers"]
    assert_equal 36, result["indexes"]
    assert_equal 0, result["tables"]["users"]
  end

  test "existing backup and restore destinations never get overwritten" do
    File.write(@archive, "existing", perm: 0o600)
    assert_raises(SyntheticSqliteBackup::Invalid) { @tool.backup(destination: @archive) }
    assert_equal "existing", File.read(@archive)
    File.unlink(@archive)
    @tool.backup(destination: @archive)
    Dir.mkdir(@restored, 0o700)
    assert_raises(SyntheticSqliteBackup::Invalid) { @tool.restore(archive: @archive, directory: @restored) }
    assert_empty Dir.children(@restored)
    assert_raises(SyntheticSqliteBackup::Invalid) { @tool.restore(archive: @archive, directory: @directory) }
  end

  test "symlinks public directories and public backup files are rejected" do
    link = File.join(@directory, "link.tar")
    File.symlink(@fixture, link)
    assert_raises(SyntheticSqliteBackup::Invalid) { @tool.backup(destination: link) }
    assert_raises(SyntheticSqliteBackup::Invalid) { @tool.verify(link) }
    public_dir = File.join(@directory, "public")
    Dir.mkdir(public_dir, 0o755)
    assert_raises(SyntheticSqliteBackup::Invalid) { @tool.backup(destination: File.join(public_dir, "bad.tar")) }
    @tool.backup(destination: @archive)
    File.chmod(0o644, @archive)
    assert_raises(SyntheticSqliteBackup::Invalid) { @tool.verify(@archive) }
  end

  test "truncated and tampered archives cannot be restored" do
    @tool.backup(destination: @archive)
    original = File.binread(@archive)
    [ original[0, 128], original.sub("SQLite format 3", "SQLite broken 3") ].each do |bytes|
      File.binwrite(@archive, bytes)
      assert_raises(SyntheticSqliteBackup::Invalid) { @tool.verify(@archive) }
      assert_raises(SyntheticSqliteBackup::Invalid) { @tool.restore(archive: @archive, directory: @restored) }
      assert_not File.exist?(File.join(@restored, "RESTORED.json"))
      FileUtils.remove_entry(@restored) if File.directory?(@restored)
    end
    File.binwrite(@archive, original)
    assert @tool.verify(@archive)["verified"]
  end

  test "SQLite incomplete copy error code cannot be reported as success" do
    factory = SQLite3::Backup.method(:new)
    SQLite3::Backup.stub(:new, ->(*args) {
      instance = factory.call(*args)
      instance.define_singleton_method(:step) { |_pages| SQLite3::Constants::ErrorCode::IOERR }
      instance
    }) do
      assert_raises(SyntheticSqliteBackup::Invalid) { @tool.backup(destination: @archive) }
    end
    assert_not File.exist?(@archive)
  end

  test "publication and fsync errors never announce success" do
    before = snapshot
    File.stub(:link, ->(*) { raise Errno::ENOSPC }) do
      assert_raises(SyntheticSqliteBackup::Invalid) { @tool.backup(destination: @archive) }
    end
    assert_not File.exist?(@archive)
    factory = File.method(:open)
    File.stub(:open, ->(path, *args, &block) {
      factory.call(path, *args) do |file|
        file.define_singleton_method(:fsync) { raise Errno::EIO } if path.end_with?("package.tar")
        block.call(file)
      end
    }) do
      assert_raises(SyntheticSqliteBackup::Invalid) { @tool.backup(destination: @archive) }
    end
    assert_not File.exist?(@archive)
    check_source(before)
  end

  test "failure before revoking sessions cannot publish a servable destination" do
    before = snapshot
    @tool.backup(destination: @archive)
    assert_raises(SyntheticSqliteBackup::Invalid) do
      @tool.restore(archive: @archive, directory: @restored) do |stage|
        raise IOError, "synthetic failure" if stage == :before_auth_revocation
      end
    end
    assert_not File.exist?(File.join(@restored, "RESTORED.json"))
    assert_not File.exist?(File.join(@restored, "synthetic.sqlite3"))
    check_source(before)
  end

  test "abrupt death during backup or restore leaves no completion marker" do
    before = snapshot
    @tool.backup(destination: @archive)
    [ :backup_step, :before_auth_revocation ].each do |point|
      pipe, writer = IO.pipe
      pending = File.join(@directory, "killed-backup.tar")
      directory = File.join(@directory, "killed-restore")
      pid = fork do
        pipe.close
        hook = ->(stage) { if stage == point; writer.write("ready"); writer.flush; sleep; end }
        if point == :backup_step
          @tool.backup(destination: pending, &hook)
        else
          @tool.restore(archive: @archive, directory: directory, &hook)
        end
        exit! 1
      end
      writer.close
      assert_equal "ready", Timeout.timeout(10) { pipe.read(5) }
      Process.kill("KILL", pid)
      _, status = Process.wait2(pid)
      pid = nil
      pipe.close
      assert status.signaled?
      assert_not File.exist?(pending)
      assert_not File.exist?(File.join(directory, "RESTORED.json"))
      check_source(before)
    ensure
      pipe&.close unless pipe&.closed?
      writer&.close unless writer&.closed?
      if pid
        Process.kill("KILL", pid)
        Process.wait(pid)
      end
    end
  end

  test "repeated restore is refused and readiness cannot be forged by an empty marker" do
    @tool.backup(destination: @archive)
    @tool.restore(archive: @archive, directory: @restored)
    target = tool(database: File.join(@restored, "synthetic.sqlite3"), fixture: File.join(@restored, "fixture.json"))
    original = snapshot(File.join(@restored, "synthetic.sqlite3"))
    assert_raises(SyntheticSqliteBackup::Invalid) { @tool.restore(archive: @archive, directory: @restored) }
    assert_equal original, snapshot(File.join(@restored, "synthetic.sqlite3"))
    File.write(File.join(@restored, "RESTORED.json"), "{}")
    assert_raises(SyntheticSqliteBackup::Invalid) { target.runtime(directory: @restored) }
  end

  test "extra TAR paths trailing payload and missing finalization are refused" do
    @tool.backup(destination: @archive)
    original = File.binread(@archive)
    rewrite_archive { |entries| entries["../outside.txt"] = "not extracted" }
    assert_raises(SyntheticSqliteBackup::Invalid) { @tool.verify(@archive) }
    assert_not File.exist?(File.join(File.dirname(@directory), "outside.txt"))
    File.binwrite(@archive, original + "hidden payload".ljust(512, "\0") + "\0" * 1024)
    assert_raises(SyntheticSqliteBackup::Invalid) { @tool.verify(@archive) }
    File.binwrite(@archive, original[0...-1024])
    assert_raises(SyntheticSqliteBackup::Invalid) { @tool.verify(@archive) }
  end

  test "manifest-only tampering and incompatible format are detected" do
    @tool.backup(destination: @archive)
    original = File.binread(@archive)
    rewrite_archive do |entries|
      manifest = JSON.parse(entries.fetch("manifest.json"))
      manifest["artifact_id"] = "modified"
      entries["manifest.json"] = JSON.generate(manifest)
    end
    assert_raises(SyntheticSqliteBackup::Invalid) { @tool.verify(@archive) }
    File.binwrite(@archive, original)
    rewrite_archive do |entries|
      manifest = JSON.parse(entries.fetch("manifest.json"))
      manifest["version"] = 99
      manifest["manifest_sha256"] = SqliteBackupSnapshot.fingerprint(manifest.except("manifest_sha256"))
      entries["manifest.json"] = JSON.generate(manifest)
    end
    assert_raises(SyntheticSqliteBackup::Invalid) { @tool.verify(@archive) }
  end

  test "directory fsync failure after publication remains unconfirmed and no overwrite is attempted" do
    factory = File.method(:open)
    File.stub(:open, ->(path, *args, &block) {
      factory.call(path, *args) do |file|
        file.define_singleton_method(:fsync) { raise Errno::EIO } if path == @directory
        block.call(file)
      end
    }) do
      assert_raises(SyntheticSqliteBackup::Invalid) { @tool.backup(destination: @archive) }
    end
    assert File.exist?(@archive)
    # A readable complete artifact may remain, but the failed operation never returns success.
    assert @tool.verify(@archive)["verified"]
    assert_raises(SyntheticSqliteBackup::Invalid) { @tool.backup(destination: @archive) }
  end

  test "private unwritable directory and destination equal to source are refused" do
    before = snapshot
    assert_raises(SyntheticSqliteBackup::Invalid) { @tool.backup(destination: @database) }
    File.chmod(0o500, @directory)
    assert_raises(SyntheticSqliteBackup::Invalid) { @tool.backup(destination: @archive) }
    assert_not File.exist?(@archive)
  ensure
    File.chmod(0o700, @directory)
    check_source(before)
  end

  test "real exclusive SQLite contention is recoverable and leaves source intact" do
    before = snapshot
    # A separate synthetic DELETE-mode case exercises a reader lock. Ordinary WAL writers
    # are tested separately and must NOT block the online backup's read snapshot.
    @db.execute("PRAGMA journal_mode=DELETE")
    @db.close
    @db = nil
    reader, writer = IO.pipe
    release, notifier = IO.pipe
    pid = fork do
      reader.close
      notifier.close
      connection = SQLite3::Database.new(@database)
      connection.execute("BEGIN EXCLUSIVE")
      writer.write("ready")
      writer.flush
      release.read(1)
      connection.execute("ROLLBACK")
      connection.close
      exit! 0
    end
    writer.close
    release.close
    assert_equal "ready", Timeout.timeout(10) { reader.read(5) }
    assert_raises(SyntheticSqliteBackup::Busy) { @tool.backup(destination: @archive) }
    assert_not File.exist?(@archive)
    notifier.write("x")
    notifier.close
    _, status = Process.wait2(pid)
    pid = nil
    assert status.success?
    assert_equal before, snapshot
  ensure
    reader&.close
    notifier&.close unless notifier&.closed?
    if pid
      Process.kill("KILL", pid)
      Process.wait(pid)
    end
  end
end
