require "sqlite3"
require "json"
require "digest"
require "securerandom"
require "tmpdir"
require "rubygems/package"
require "time"
require_relative "legacy_snapshot_archive"
require_relative "sqlite_backup_snapshot"

# No Rails environment dependency. Only explicit, owner-private synthetic fixtures.
class SyntheticSqliteBackup
  class Invalid < StandardError; end
  class Busy < Invalid; end
  FORMAT = "accio-synthetic-sqlite-backup"
  VERSION = 1
  MEMBERS = %w[database.sqlite3 manifest.json].freeze

  def initialize(fixture:, database:, environment:, checkout:)
    LegacySnapshotArchive.new(fixture: fixture, database: database, environment: environment, checkout: checkout)
    @database = File.realpath(database)
    @checkout = File.realpath(checkout)
    @contract = parse(File.binread(File.expand_path("../../config/sqlite_backup_contract.json", __dir__)))
  rescue LegacySnapshotArchive::Invalid, SystemCallError, JSON::ParserError
    raise Invalid, "Fixture sintética ou contrato indisponível"
  end

  def backup(destination:, &observe)
    destination = new_path(destination, extension: ".tar")
    with_work(File.dirname(destination)) do |work|
      copy = File.join(work, "database.sqlite3")
      source = open_readonly(@database)
      capture_started_at = Time.now.utc.iso8601(6)
      begin
        source.execute("BEGIN")
        validate_database!(source)
        snapshot = SqliteBackupSnapshot.read(source)
        compatible!(snapshot)
        observe&.call(:snapshot_pinned)
        online_copy(source, copy) { |stage| observe&.call(stage) }
        copied = inspect_file(copy)
        raise Invalid, "Backup não corresponde à leitura fixada" unless copied == snapshot
      ensure
        source.execute("ROLLBACK") if source.transaction_active?
        source.close
      end
      manifest = { "format" => FORMAT, "version" => VERSION, "artifact_id" => SecureRandom.uuid,
        "capture_started_at" => capture_started_at, "verified_at" => Time.now.utc.iso8601(6),
        "capture_point" => "first read in pinned SQLite read transaction",
        "database_sha256" => Digest::SHA256.file(copy).hexdigest,
        "migrations" => @contract.fetch("migrations"), "snapshot" => snapshot }
      manifest["manifest_sha256"] = SqliteBackupSnapshot.fingerprint(manifest)
      write_private(File.join(work, "manifest.json"), JSON.generate(manifest))
      archive = File.join(work, "package.tar")
      File.open(archive, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
        file.binmode
        Gem::Package::TarWriter.new(file) do |tar|
          MEMBERS.each do |name|
            member = File.join(work, name)
            tar.add_file_simple(name, 0o600, File.size(member)) { |entry| File.open(member, "rb") { |input| IO.copy_stream(input, entry) } }
          end
        end
        file.flush
        file.fsync
      end
      verify(archive)
      observe&.call(:backup_verified)
      publish(archive, destination)
      verify(destination)
    end
  rescue SQLite3::BusyException, SQLite3::LockedException
    raise Busy, "Contenção SQLite; tente novamente com destino novo"
  rescue SQLite3::Exception, SystemCallError, IOError, Gem::Package::TarInvalidError
    raise Invalid, "Backup não confirmado; confira o destino privado"
  end

  def verify(archive)
    with_work(File.dirname(private_file(archive))) do |work|
      manifest = unpack_verified(archive, work)
      summary(manifest)
    end
  rescue SQLite3::Exception, SystemCallError, IOError, Gem::Package::TarInvalidError, EOFError
    raise Invalid, "Arquivo de backup inválido ou indisponível"
  end

  def restore(archive:, directory:, &observe)
    archive = private_file(archive)
    directory = new_path(directory)
    # mkdir is the no-clobber reservation. No ready marker or public DB exists yet.
    Dir.mkdir(directory, 0o700)
    with_work(directory) do |work|
      manifest = unpack_verified(archive, work)
      target = File.join(work, "synthetic.sqlite3")
      input = open_readonly(File.join(work, "database.sqlite3"))
      begin
        online_copy(input, target) { |stage| observe&.call(stage) }
      ensure
        input.close
      end
      raise Invalid, "Restauração não é fiel" unless inspect_file(target) == manifest.fetch("snapshot")
      observe&.call(:restore_fidelity_verified)
      security = revoke_restored_sessions(target, manifest.fetch("snapshot")) { observe&.call(:before_auth_revocation) }
      observe&.call(:auth_sessions_revoked)
      # New runtime configuration, not copied from the origin and NEVER included in backup TAR.
      write_private(File.join(work, "runtime-secret"), SecureRandom.hex(64))
      write_private(File.join(work, "fixture.json"), JSON.generate({ format: "accio-f3a-synthetic", version: 1, database: "synthetic.sqlite3" }))
      ready = { "format" => "accio-synthetic-restored", "version" => VERSION, "prepared" => true,
        "backup_artifact_id" => manifest.fetch("artifact_id"), "prepared_at" => Time.now.utc.iso8601(6),
        "security" => security, "snapshot_before_security" => manifest.fetch("snapshot") }
      write_private(File.join(work, "RESTORED.json"), JSON.generate(ready))
      observe&.call(:restore_prepared)
      %w[synthetic.sqlite3 runtime-secret fixture.json RESTORED.json].each do |name|
        publish(File.join(work, name), File.join(directory, name))
      end
      self.class.new(fixture: File.join(directory, "fixture.json"), database: File.join(directory, "synthetic.sqlite3"),
        environment: "test", checkout: @checkout).runtime(directory: directory)
      { "prepared" => true, "revoked_sessions" => security.fetch("revoked_sessions"), "fidelity_verified_before_security" => true }
    end
  rescue SQLite3::BusyException, SQLite3::LockedException
    raise Busy, "Contenção no destino sintético; nenhuma sessão original alterada"
  rescue SQLite3::Exception, SystemCallError, IOError, Gem::Package::TarInvalidError, EOFError
    raise Invalid, "Restauração não confirmada; destino não deve ser servido"
  end

  # Used by the guarded QA launcher on every start, including process restarts.
  # A caller must not print the returned runtime secret.
  def runtime(directory:)
    directory = private_directory(directory)
    raise Invalid, "Destino não corresponde à fixture" unless @database == File.join(directory, "synthetic.sqlite3")
    ready = parse(read_private(File.join(directory, "RESTORED.json")))
    unless ready.is_a?(Hash) && ready["format"] == "accio-synthetic-restored" && ready["version"] == VERSION && ready["prepared"] == true
      raise Invalid, "Preparação incompleta; HTTP proibido"
    end
    key = read_private(File.join(directory, "runtime-secret"))
    raise Invalid, "Configuração de runtime incompatível" unless key.match?(/\A[0-9a-f]{128}\z/)
    db = open_readonly(@database)
    begin
      db.execute("BEGIN")
      validate_database!(db)
      compatible!(SqliteBackupSnapshot.read(db))
      raise Invalid, "Política de segurança incompatível" unless ready["security"].is_a?(Hash)
      floor = ready.fetch("security").fetch("original_auth_sequence")
      raise Invalid, "Segurança do destino incompatível" unless floor.is_a?(Integer) && floor >= 0
      raise Invalid, "Sessão antiga encontrada; HTTP proibido" unless db.get_first_value("SELECT count(*) FROM auth_sessions WHERE id <= ?", [ floor ]).zero?
    ensure
      db.execute("ROLLBACK") if db.transaction_active?
      db.close
    end
    key
  rescue SQLite3::Exception, SystemCallError, KeyError, TypeError
    raise Invalid, "Preparação não comprovada; HTTP proibido"
  end

  private

  def online_copy(source, path)
    File.open(path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) { }
    target = SQLite3::Database.new(path)
    target.busy_timeout(5000)
    target.execute("PRAGMA synchronous=FULL")
    backup = SQLite3::Backup.new(target, "main", source, "main")
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      code = backup.step(16)
      yield :backup_step if block_given?
      break if code == SQLite3::Constants::ErrorCode::DONE
      if [ SQLite3::Constants::ErrorCode::BUSY, SQLite3::Constants::ErrorCode::LOCKED ].include?(code)
        raise Busy, "SQLite ocupado; cópia incompleta" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.02
      elsif code != SQLite3::Constants::ErrorCode::OK
        raise Invalid, "SQLite recusou a cópia; nenhum sucesso anunciado"
      end
    end
    backup.finish
    backup = nil
    # Only the NEW offline destination changes mode. Source WAL/pragmas are untouched.
    raise Invalid, "Destino não autocontido" unless target.get_first_value("PRAGMA journal_mode=DELETE") == "delete"
    target.close
    target = nil
    sync_file(path)
  ensure
    backup&.finish
    target&.close
  end

  def revoke_restored_sessions(path, expected)
    db = SQLite3::Database.new(path)
    db.busy_timeout(5000)
    db.execute("PRAGMA foreign_keys=ON")
    db.execute("PRAGMA synchronous=FULL")
    db.execute("BEGIN IMMEDIATE")
    count = db.get_first_value("SELECT count(*) FROM auth_sessions")
    sequence = db.get_first_value("SELECT seq FROM sqlite_sequence WHERE name='auth_sessions'") || 0
    yield
    db.execute("DELETE FROM auth_sessions")
    after = SqliteBackupSnapshot.read(db)
    unless after.fetch("schema") == expected.fetch("schema") &&
        after.fetch("tables").except("auth_sessions") == expected.fetch("tables").except("auth_sessions") &&
        after.fetch("tables").fetch("auth_sessions").fetch("rows").zero?
      raise Invalid, "Sanitização alterou dados inesperados"
    end
    validate_database!(db)
    db.execute("COMMIT")
    { "revoked_sessions" => count, "original_auth_sequence" => sequence, "fresh_runtime_secret_required" => true }
  ensure
    if db
      db.execute("ROLLBACK") if db.transaction_active?
      db.close
      sync_file(path)
    end
  end

  def unpack_verified(archive, work)
    archive = private_file(archive)
    seen = []
    File.open(archive, File::RDONLY | File::NOFOLLOW) do |input|
      input.binmode
      raise Invalid, "Pacote incompleto" if input.stat.size < 1024 || input.stat.size % 512 != 0
      input.seek(-1024, IO::SEEK_END)
      raise Invalid, "Finalização TAR ausente" unless input.read(1024) == "\0" * 1024
      input.rewind
      Gem::Package::TarReader.new(input) do |tar|
        tar.each do |entry|
          name = entry.full_name
          unless MEMBERS.include?(name) && !seen.include?(name) && entry.file? && entry.header.size <= input.stat.size
            raise Invalid, "Membro do pacote incompatível"
          end
          raise Invalid, "Manifesto excessivo" if name == "manifest.json" && entry.header.size > 1_048_576
          seen << name
          File.open(File.join(work, name), File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |output|
            output.binmode
            copied = IO.copy_stream(entry, output)
            raise Invalid, "Membro truncado" unless copied == entry.header.size
          end
        end
      end
      # Our format has only these members and zero TAR padding, no hidden trailing payload.
      while (padding = input.read(65_536))
        raise Invalid, "Conteúdo extra no pacote" unless padding.bytes.all?(&:zero?)
      end
      raise Invalid, "Pacote truncado" unless input.stat.size % 512 == 0
    end
    raise Invalid, "Pacote incompleto" unless seen.sort == MEMBERS.sort
    manifest = parse(read_private(File.join(work, "manifest.json")))
    unless manifest.is_a?(Hash) && manifest["format"] == FORMAT && manifest["version"] == VERSION && manifest["migrations"] == @contract.fetch("migrations")
      raise Invalid, "Manifesto incompatível"
    end
    unless manifest["manifest_sha256"] == SqliteBackupSnapshot.fingerprint(manifest.except("manifest_sha256"))
      raise Invalid, "Hash do manifesto incompatível"
    end
    database = File.join(work, "database.sqlite3")
    raise Invalid, "Hash do banco incompatível" unless Digest::SHA256.file(database).hexdigest == manifest["database_sha256"]
    raise Invalid, "Conteúdo lógico incompatível" unless inspect_file(database) == manifest["snapshot"]
    manifest
  end

  def inspect_file(path)
    db = open_readonly(path)
    begin
      validate_database!(db)
      snapshot = SqliteBackupSnapshot.read(db)
      compatible!(snapshot)
      snapshot
    ensure
      db.close
    end
  end

  def compatible!(snapshot)
    objects = snapshot.fetch("schema").fetch("objects")
    unless @contract.fetch("schema_sha256").include?(snapshot.fetch("schema_sha256")) &&
        snapshot.fetch("tables").fetch("schema_migrations").fetch("sha256") == @contract.fetch("migrations_sha256") &&
        objects.count { |row| row[0] == "trigger" } == 25 && objects.count { |row| row[0] == "index" } == 36
      raise Invalid, "Schema incompatível com esta versão da aplicação"
    end
  end

  def validate_database!(db)
    raise Invalid, "Integridade SQLite inválida" unless db.execute("PRAGMA integrity_check") == [ [ "ok" ] ] && db.execute("PRAGMA foreign_key_check").empty?
  end

  def open_readonly(path)
    db = SQLite3::Database.new(private_file(path), readonly: true)
    db.busy_timeout(5000)
    db.execute("PRAGMA query_only=ON")
    db
  end

  def summary(manifest)
    { "verified" => true, "format_version" => VERSION, "tables" => manifest.fetch("snapshot").fetch("tables").transform_values { |t| t.fetch("rows") }, "triggers" => 25, "indexes" => 36 }
  end

  def parse(bytes)
    JSON.parse(bytes, allow_duplicate_key: false)
  rescue JSON::ParserError
    raise Invalid, "JSON incompatível"
  end

  def private_directory(path)
    raise Invalid, "Diretório explícito obrigatório" unless path.is_a?(String) && !path.empty?
    expanded = File.expand_path(path)
    stat = File.stat(expanded)
    unless File.realpath(expanded) == expanded && stat.directory? && stat.uid == Process.uid && (stat.mode & 0o077).zero? &&
        expanded != @checkout && !expanded.start_with?(@checkout + File::SEPARATOR)
      raise Invalid, "Diretório privado fora do checkout obrigatório"
    end
    expanded
  end

  def private_file(path)
    raise Invalid, "Arquivo explícito obrigatório" unless path.is_a?(String) && !path.empty?
    expanded = File.expand_path(path)
    private_directory(File.dirname(expanded))
    stat = File.lstat(expanded)
    unless stat.file? && !stat.symlink? && stat.uid == Process.uid && (stat.mode & 0o077).zero? && stat.nlink == 1
      raise Invalid, "Arquivo privado regular sem links obrigatório"
    end
    expanded
  end

  def read_private(path)
    File.open(private_file(path), File::RDONLY | File::NOFOLLOW, &:read)
  end

  def new_path(path, extension: nil)
    raise Invalid, "Destino explícito obrigatório" unless path.is_a?(String) && !path.empty?
    expanded = File.expand_path(path)
    private_directory(File.dirname(expanded))
    raise Invalid, "Destino existente; sobrescrita proibida" if File.exist?(expanded) || File.symlink?(expanded)
    raise Invalid, "Extensão incompatível" if extension && !expanded.end_with?(extension)
    raise Invalid, "Destino coincide com origem" if expanded == @database
    expanded
  end

  def with_work(parent)
    parent = private_directory(parent)
    Dir.mktmpdir(".accio-sqlite-", parent) { |work| yield work }
  end

  def write_private(path, bytes)
    File.open(path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
      file.write(bytes)
      file.flush
      file.fsync
    end
  end

  def sync_file(path)
    File.open(path, File::RDONLY | File::NOFOLLOW, &:fsync)
  end

  def publish(source, destination)
    File.link(source, destination)
    File.unlink(source)
    File.open(File.dirname(destination), File::RDONLY, &:fsync)
  end
end
