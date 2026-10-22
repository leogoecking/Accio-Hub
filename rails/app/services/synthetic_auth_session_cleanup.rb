require "date"
require "time"
require_relative "legacy_snapshot_archive"
require_relative "sqlite_backup_snapshot"

# Local maintenance only. Never loads Rails, opens a default DB, or creates a DB.
class SyntheticAuthSessionCleanup
  class Invalid < StandardError; end
  class Busy < StandardError; end

  CONFIRMATION = "DELETE_EXPIRED_AUTH_SESSIONS".freeze
  BATCH_SIZE = 100

  def initialize(fixture:, database:, environment:, checkout:, clock: -> { Time.now.utc })
    @options = { fixture: fixture, database: database, environment: environment, checkout: checkout }
    validate_files!
    @database = File.expand_path(database)
    @clock = clock
    @contract = JSON.parse(File.read(File.expand_path("../../config/sqlite_backup_contract.json", __dir__)))
  end

  def inventory(&observe)
    operate(delete: false, observe: observe)
  end

  def cleanup(confirmation:, &observe)
    raise Invalid, "Confirmação explícita obrigatória" unless confirmation == CONFIRMATION
    operate(delete: true, observe: observe)
  end

  private

  def validate_files!
    LegacySnapshotArchive.new(**@options)
    unless [ @options[:fixture], @options[:database] ].all? { |path| (File.stat(path).mode & 0o400) == 0o400 }
      raise Invalid, "Leitura privada indisponível"
    end
  rescue LegacySnapshotArchive::Invalid
    raise Invalid, "Ambiente, fixture ou banco sintético privado incompatível"
  end

  def operate(delete:, observe:)
    validate_files!
    raise Invalid, "Escrita privada indisponível" if delete && (File.stat(@database).mode & 0o200).zero?
    # One instant for the entire execution, including lock waiting and all pages.
    cutoff = @clock.call.utc.floor(6)
    observe&.call(:cutoff_fixed)
    flags = delete ? SQLite3::Constants::Open::READWRITE : SQLite3::Constants::Open::READONLY
    db = SQLite3::Database.new(@database, flags: flags)
    db.busy_timeout(5000)
    db.execute("PRAGMA foreign_keys=ON")
    if delete
      db.execute("PRAGMA synchronous=FULL")
    else
      db.execute("PRAGMA query_only=ON")
    end
    db.execute(delete ? "BEGIN IMMEDIATE" : "BEGIN")
    validate_schema!(db)
    raise Invalid, "Administrador sintético ausente" unless db.get_first_value("SELECT 1 FROM users WHERE id=1")
    observe&.call(:transaction_open)
    result = { "mode" => delete ? "cleanup" : "dry_run", "cutoff_utc" => cutoff.iso8601(6),
      "scanned" => 0, "expired" => 0, "active" => 0, "unclassified_preserved" => 0, "deleted" => 0 }
    cursor = nil
    loop do
      rows = db.execute("SELECT id, expires_at, typeof(expires_at) FROM auth_sessions WHERE user_id=1 AND (? IS NULL OR id > ?) ORDER BY id LIMIT ?", [ cursor, cursor, BATCH_SIZE ])
      break if rows.empty?
      rows.each do |id, raw, sql_type|
        result["scanned"] += 1
        expiration = sql_type == "text" ? expiration_time(raw) : nil
        if expiration.nil?
          result["unclassified_preserved"] += 1
        elsif expiration > cutoff
          result["active"] += 1
        else
          result["expired"] += 1
          if delete
            # Repeat owner and exact observed expiration. No callbacks or other tables.
            db.execute("DELETE FROM auth_sessions WHERE id=? AND user_id=1 AND expires_at=? AND expires_at<=?",
              [ id, raw, cutoff.strftime("%Y-%m-%d %H:%M:%S.%6N") ])
            raise Invalid, "Seleção de expiração incompatível; transação revertida" unless db.changes == 1
            result["deleted"] += 1
          end
        end
      end
      cursor = rows.last.first
      observe&.call(:page_processed)
    end
    observe&.call(:before_commit)
    db.execute("COMMIT")
    result.merge("committed" => delete)
  rescue SQLite3::BusyException, SQLite3::LockedException
    raise Busy, "Contenção SQLite; limpeza não confirmada, tente novamente explicitamente"
  rescue SQLite3::Exception, SystemCallError, ArgumentError, TypeError
    raise Invalid, "Operação indisponível; nenhuma limpeza confirmada"
  ensure
    db&.execute("ROLLBACK") if db&.transaction_active?
    db&.close
  end

  def validate_schema!(db)
    fingerprint = SqliteBackupSnapshot.fingerprint(SqliteBackupSnapshot.schema(db))
    unless @contract.fetch("schema_sha256").include?(fingerprint) && db.get_first_value("PRAGMA foreign_keys") == 1 &&
        db.get_first_value("PRAGMA integrity_check") == "ok" && db.execute("PRAGMA foreign_key_check").empty?
      raise Invalid, "Estrutura ou integridade incompatível"
    end
  end

  # Rails writes UTC SQL timestamps. Do not guess a timezone or coerce bad dates.
  # Date-only, noncanonical, BLOB, numeric and otherwise ambiguous data stay intact.
  def expiration_time(raw)
    return unless raw.instance_of?(String) && raw.valid_encoding?
    match = /\A(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?\z/.match(raw)
    return unless match
    year, month, day, hour, minute, second = match.captures.first(6).map(&:to_i)
    return unless Date.valid_date?(year, month, day) && hour < 24 && minute < 60 && second < 60
    Time.utc(year, month, day, hour, minute, second, match[7].to_s.ljust(6, "0").to_i)
  rescue ArgumentError
    nil
  end
end
