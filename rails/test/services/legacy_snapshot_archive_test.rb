require "test_helper"
require "tmpdir"
require "fileutils"
require "minitest/mock"
require "timeout"

class LegacySnapshotArchiveTest < ActiveSupport::TestCase
  setup do
    @directory = Dir.mktmpdir("accio-f3a-unit-")
    @database = File.join(@directory, "synthetic.sqlite3")
    @fixture = File.join(@directory, "fixture.json")
    File.write(@fixture, JSON.generate({ format: "accio-f3a-synthetic", version: 1, database: "synthetic.sqlite3" }), perm: 0o600)
    @db = SQLite3::Database.new(@database)
    File.chmod(0o600, @database)
    @db.execute("CREATE TABLE user_preferences (id INTEGER, user_id INTEGER, lock_version INTEGER, preferences_schema_version INTEGER, initialized_at TEXT, legacy_cookie_imported_at TEXT, legacy_cookie_digest TEXT, updated_at TEXT, legacy_cookie_backup TEXT)")
    @archive = build_archive
    @destination = File.join(@directory, "export.json")
  end

  teardown do
    @db&.close
    FileUtils.remove_entry(@directory)
  end

  def build_archive(**options)
    LegacySnapshotArchive.new(**{ fixture: @fixture, database: @database, environment: "test", checkout: Rails.root.parent.to_s }.merge(options))
  end

  def candidate(**options)
    { "source" => "p1.1-cookie", "raw" => "synthetic opaque cookie", "digest" => Digest::SHA256.hexdigest("synthetic opaque cookie"), "valid" => true, "value" => Studio.defaults }.merge(options.transform_keys(&:to_s))
  end

  def seed(value, raw: nil)
    text = raw || (value && JSON.pretty_generate(value))
    @db.execute("INSERT INTO user_preferences VALUES (1,1,7,1,'2026-01-01','2026-01-02',?,'2026-09-01',?)", [ candidate["digest"], text ])
    text
  end

  def round_trip(value)
    original = seed(value)
    before = @db.execute("SELECT * FROM user_preferences")
    exported = @archive.export(destination: @destination)
    reopened = @archive.verify(@destination)
    assert_equal exported, reopened
    assert_equal original&.b, @archive.original(reopened.fetch("capture"))&.b unless original.nil?
    assert_nil @archive.original(reopened.fetch("capture")) if original.nil?
    assert_equal before, @db.execute("SELECT * FROM user_preferences")
    assert_equal 7, reopened.dig("capture", "record", "lock_version")
    assert_equal 0o600, File.stat(@destination).mode & 0o777
    assert_empty Dir.glob(File.join(@directory, ".accio-*.tmp"))
    reopened
  end

  test "inventory of absent preference and absent backup never initializes anything" do
    first = @archive.inventory
    assert_equal false, first["preference_present"]
    assert_equal 0, first["snapshot_count"]
    assert_equal first, @archive.inventory
    content = @archive.export(destination: @destination)
    assert_nil content.dig("capture", "record")
    assert_empty @db.execute("SELECT * FROM user_preferences")
    File.unlink(@destination)
    round_trip(nil)
    assert_equal false, @archive.inventory["snapshot_present"]
  end

  test "root and unknown fields preserve literal JSON bytes and declared origin privately" do
    content = round_trip(candidate(extra: { "future" => [ 1, nil, false, "ação\nlinha" ] }, source: "private source"))
    info = content["inventory"]
    assert_equal 1, info["snapshot_count"]
    assert_equal "unknown", info["candidates"][0]["source"]
    assert_not_includes JSON.generate(info), "private source"
    assert_not_includes JSON.generate(info), "synthetic opaque cookie"
    assert_equal 1, info["unknown_root_fields"]
    assert_equal "match", info["candidates"][0]["digest_status"]
  end

  test "invalid root remains opaque without applying or repairing values" do
    round_trip(candidate(valid: false, value: { "theme" => "unsupported" }, raw: [ "invalid raw type" ]))
    info = @archive.inventory["candidates"][0]
    assert_equal false, info["raw_string"]
    assert_equal false, info["declared_valid"]
    assert_equal "unverifiable", info["digest_status"]
  end

  test "retained only and root plus retained candidates preserve all contents" do
    [ false, true ].each_with_index do |root, index|
      value = root ? candidate : {}
      extra = candidate(valid: false, value: nil)
      value["retained_candidates"] = { extra["digest"] => extra, "unknown-key" => { "new_field" => [ 42 ] } }
      @db.execute("DELETE FROM user_preferences")
      @destination = File.join(@directory, "export-#{index}.json")
      content = round_trip(value)
      assert_equal root ? 3 : 2, content["inventory"]["snapshot_count"]
      assert_equal 2, content["inventory"]["additional_count"]
    end
  end

  test "missing origins digest mismatch and malformed retained structure are explicit warnings" do
    value = candidate(digest: "0" * 64)
    value.delete("source")
    value["retained_candidates"] = [ "opaque extension" ]
    content = round_trip(value)
    assert_equal "mismatch", content["inventory"]["candidates"][0]["digest_status"]
    assert_equal false, content["inventory"]["candidates"][0]["source_present"]
    assert_includes content["inventory"]["warnings"], "retained_candidates_not_map; preserved_opaque"
  end

  test "unrecognized object is preserved and marked opaque" do
    content = round_trip({ "future_schema" => { "x" => [ 1, 2 ] } })
    assert_includes content["inventory"]["warnings"], "unrecognized_root_preserved_opaque"
  end

  test "digest of the original Unicode raw and aggregate digest are checked separately" do
    raw = "captura sintética\\ncom acentuação"
    original = seed(candidate(raw: raw, digest: Digest::SHA256.hexdigest(raw)))
    assert_equal "match", @archive.inventory["candidates"][0]["digest_status"]
    assert_equal "mismatch", @archive.inventory["aggregate_digest_status"]
    content = @archive.export(destination: @destination)
    assert_equal original.b, @archive.original(content["capture"]).b
    assert_includes content["inventory"]["warnings"], "aggregate_digest_mismatch"
  end

  test "malformed duplicated and non UTF8 JSON are blocked without losing source" do
    [ '{"broken":', '{"raw":"one","raw":"two"}', "{\"raw\":\"\xFF\"}".b ].each do |raw|
      @db.execute("DELETE FROM user_preferences")
      seed(nil, raw: raw)
      before = @db.execute("SELECT * FROM user_preferences")
      assert_not_empty @archive.inventory["blockers"]
      assert_raises(LegacySnapshotArchive::Invalid) { @archive.export(destination: @destination) }
      assert_equal before, @db.execute("SELECT * FROM user_preferences")
      assert_not File.exist?(@destination)
    end
  end

  test "existing destination and symlink are never replaced" do
    seed(candidate)
    File.write(@destination, "existing", perm: 0o600)
    assert_raises(LegacySnapshotArchive::Invalid) { @archive.export(destination: @destination) }
    assert_equal "existing", File.read(@destination)
    File.unlink(@destination)
    File.symlink(@fixture, @destination)
    original = File.binread(@fixture)
    assert_raises(LegacySnapshotArchive::Invalid) { @archive.export(destination: @destination) }
    assert_equal original, File.binread(@fixture)
    assert_raises(LegacySnapshotArchive::Invalid) { @archive.verify(@destination) }
  end

  test "public missing and checkout directories or invalid filename are refused" do
    seed(candidate)
    public_dir = File.join(@directory, "public")
    Dir.mkdir(public_dir, 0o755)
    [ File.join(public_dir, "x.json"), File.join(@directory, "missing", "x.json"), Rails.root.join("tmp", "x.json").to_s, File.join(@directory, "bad.sqlite3"), nil ].each do |path|
      assert_raises(LegacySnapshotArchive::Invalid, SystemCallError) { @archive.export(destination: path) }
    end
    symlink = File.join(@directory, "linked")
    File.symlink(@directory, symlink)
    assert_raises(LegacySnapshotArchive::Invalid) { @archive.export(destination: File.join(symlink, "x.json")) }
  end

  test "unwritable directory leaves no final artifact" do
    seed(candidate)
    File.chmod(0o500, @directory)
    assert_raises(LegacySnapshotArchive::Invalid) { @archive.export(destination: @destination) }
    assert_not File.exist?(@destination)
  ensure
    File.chmod(0o700, @directory)
  end

  test "interrupted write is never published and temporary is removed" do
    seed(candidate)
    File.stub(:link, ->(*) { raise Errno::EIO }) do
      assert_raises(LegacySnapshotArchive::Invalid) { @archive.export(destination: @destination) }
    end
    assert_not File.exist?(@destination)
    assert_empty Dir.glob(File.join(@directory, ".accio-*.tmp"))
    @archive.export(destination: @destination)
    assert @archive.verify(@destination)
  end

  test "disk failure after partial write never exposes a final file" do
    seed(candidate)
    factory = File.method(:open)
    File.stub(:open, ->(path, *args, &block) {
      factory.call(path, *args) do |file|
        if File.basename(path).start_with?(".accio-")
          file.define_singleton_method(:write) do |bytes|
            syswrite(bytes[0, 20])
            raise Errno::ENOSPC
          end
        end
        block.call(file)
      end
    }) do
      assert_raises(LegacySnapshotArchive::Invalid) { @archive.export(destination: @destination) }
    end
    assert_not File.exist?(@destination)
    assert_empty Dir.glob(File.join(@directory, ".accio-*.tmp"))
    assert_equal 7, @db.get_first_value("SELECT lock_version FROM user_preferences")
  end

  test "a competing publisher cannot clobber an existing final file" do
    seed(candidate)
    factory = File.method(:link)
    File.stub(:link, ->(source, destination) {
      File.write(destination, "other publisher", perm: 0o600)
      factory.call(source, destination)
    }) do
      assert_raises(LegacySnapshotArchive::Invalid) { @archive.export(destination: @destination) }
    end
    assert_equal "other publisher", File.read(@destination)
    assert_empty Dir.glob(File.join(@directory, ".accio-*.tmp"))
  end

  test "abrupt death during write leaves only a private unannounced temporary" do
    seed(candidate)
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      factory = File.method(:open)
      File.stub(:open, ->(path, *args, &block) {
        factory.call(path, *args) do |file|
          if File.basename(path).start_with?(".accio-")
            file.define_singleton_method(:write) do |bytes|
              syswrite(bytes[0, 20])
              writer.write("ready")
              writer.flush
              sleep
            end
          end
          block.call(file)
        end
      }) { @archive.export(destination: @destination) }
      exit! 1
    end
    writer.close
    assert_equal "ready", Timeout.timeout(5) { reader.read(5) }
    Process.kill("KILL", pid)
    _, status = Process.wait2(pid)
    pid = nil
    assert status.signaled?
    assert_not File.exist?(@destination)
    temporary = Dir.glob(File.join(@directory, ".accio-*.tmp"))
    assert_equal 1, temporary.size
    assert_equal 0o600, File.stat(temporary.first).mode & 0o777
    assert_raises(LegacySnapshotArchive::Invalid) { @archive.verify(temporary.first) }
    assert_equal 7, @db.get_first_value("SELECT lock_version FROM user_preferences")
  ensure
    reader&.close
    writer&.close unless writer&.closed?
    if pid
      begin
        Process.kill("KILL", pid)
        Process.wait(pid)
      rescue Errno::ESRCH, Errno::ECHILD
        # The synthetic writer was already reaped above.
      end
    end
  end

  test "public files and hard links are refused without changing permissions" do
    seed(candidate)
    @archive.export(destination: @destination)
    File.chmod(0o644, @destination)
    assert_raises(LegacySnapshotArchive::Invalid) { @archive.verify(@destination) }
    assert_equal 0o644, File.stat(@destination).mode & 0o777
    File.chmod(0o600, @destination)
    link = File.join(@directory, "hard-link.json")
    File.link(@destination, link)
    assert_raises(LegacySnapshotArchive::Invalid) { @archive.verify(link) }
  end

  test "truncation changed digest payload and format are refused" do
    round_trip(candidate)
    bytes = File.binread(@destination)
    mutations = [ bytes[0, bytes.size / 2] ]
    body = JSON.parse(bytes)
    body["content_sha256"] = "0" * 64
    mutations << JSON.generate(body)
    body = JSON.parse(bytes)
    body["content"]["version"] = 99
    mutations << JSON.generate(body)
    body = JSON.parse(bytes)
    body["content"]["capture"]["record"]["lock_version"] += 1
    mutations << JSON.generate(body)
    mutations.each do |mutation|
      File.binwrite(@destination, mutation)
      assert_raises(LegacySnapshotArchive::Invalid) { @archive.verify(@destination) }
    end
    File.binwrite(@destination, bytes)
    assert @archive.verify(@destination)
  end

  test "guard refuses defaults wrong environment mismatched database and altered fixture" do
    [ { environment: "development" }, { database: nil }, { fixture: nil }, { database: @fixture } ].each do |options|
      assert_raises(LegacySnapshotArchive::Invalid) { build_archive(**options) }
    end
    File.write(@fixture, "{}")
    assert_raises(LegacySnapshotArchive::Invalid) { build_archive }
  end

  test "read only SQLite capture cannot execute DML and does not include unrelated credentials" do
    seed(candidate)
    traces = []
    factory = SQLite3::Database.method(:new)
    SQLite3::Database.stub(:new, ->(*args, **options) {
      assert_equal true, options[:readonly]
      connection = factory.call(*args, **options)
      connection.trace { |sql| traces << sql }
      assert_raises(SQLite3::ReadOnlyException) { connection.execute("UPDATE user_preferences SET lock_version=99") }
      traces.clear
      connection
    }) do
      @archive.inventory
    end
    assert_equal 1, traces.count { |sql| sql.start_with?("SELECT ") }
    assert traces.all? { |sql| sql.start_with?("SELECT ", "PRAGMA query_only=") }
    assert_equal 7, @db.get_first_value("SELECT lock_version FROM user_preferences")
    assert_empty LegacySnapshotArchive::METADATA & %w[password_digest email_address token secret_key_base]
  end
end
