require "base64"
require "digest"
require "json"
require "pathname"
require "securerandom"
require "sqlite3"
require "time"

# Administrative, synthetic-only round-trip. No Rails environment or writer connection needed.
class LegacySnapshotArchive
  class Invalid < StandardError; end

  FORMAT = "accio-legacy-snapshots"
  VERSION = 1
  METADATA = %w[id user_id lock_version preferences_schema_version initialized_at legacy_cookie_imported_at legacy_cookie_digest updated_at].freeze
  CANDIDATE_KEYS = %w[source digest valid value raw].freeze

  def initialize(fixture:, database:, environment:, checkout:)
    raise Invalid, "Somente ambiente test e fixture sintética explícita" unless environment == "test" && database && fixture
    @checkout = File.realpath(checkout)
    fixture = private_file(fixture)
    declaration = parse(read_private(fixture))
    unless declaration == { "format" => "accio-f3a-synthetic", "version" => 1, "database" => "synthetic.sqlite3" }
      raise Invalid, "Declaração sintética incompatível"
    end
    @database = private_file(database)
    unless @database == File.join(File.dirname(fixture), "synthetic.sqlite3")
      raise Invalid, "Banco não corresponde à fixture sintética"
    end
  rescue SystemCallError, JSON::ParserError, ArgumentError
    raise Invalid, "Fixture sintética indisponível ou incompatível"
  end

  # The JSON bytes and CAS metadata come from the SAME SELECT, not separate AR reads.
  def capture(user_id: 1)
    raise Invalid, "Administrador inválido" unless user_id.is_a?(Integer) && user_id.positive?
    private_file(@database)
    db = SQLite3::Database.new(@database, readonly: true)
    db.results_as_hash = true
    db.execute("PRAGMA query_only=ON")
    row = db.get_first_row("SELECT #{METADATA.join(',')}, legacy_cookie_backup FROM user_preferences WHERE user_id = ?", [ user_id ])
    return { "record" => nil, "backup_base64" => nil } unless row
    raw = row.fetch("legacy_cookie_backup")
    raise Invalid, "Tipo SQL incompatível" unless raw.nil? || raw.is_a?(String)
    { "record" => row.slice(*METADATA), "backup_base64" => raw && Base64.strict_encode64(raw.b) }
  rescue SQLite3::Exception
    raise Invalid, "Leitura sintética indisponível; nenhum dado alterado"
  ensure
    db&.close
  end

  def inventory(capture = self.capture)
    record = capture.fetch("record")
    raw = original(capture)
    result = { "preference_present" => !record.nil?, "cas_version" => record && record["lock_version"],
      "snapshot_present" => !raw.nil?, "snapshot_count" => 0, "additional_count" => 0,
      "aggregate_digest_status" => record && record["legacy_cookie_digest"] ? "unverifiable" : "absent",
      "candidates" => [], "unknown_root_fields" => 0, "blockers" => [], "warnings" => [],
      "candidate_dates" => "unknown; imported_at is initial import, updated_at is not candidate age" }
    return result unless raw
    value = parse(raw)
    unless value.is_a?(Hash)
      result["blockers"] << "backup_not_object"
      return result
    end
    result["unknown_root_fields"] = (value.keys - CANDIDATE_KEYS - [ "retained_candidates" ]).size
    if record && record["legacy_cookie_digest"] && value["raw"].is_a?(String)
      result["aggregate_digest_status"] = record["legacy_cookie_digest"] == Digest::SHA256.hexdigest(value["raw"]) ? "match" : "mismatch"
    end
    if (value.keys & CANDIDATE_KEYS).any?
      result["candidates"] << candidate_info(value, "root")
    end
    if value.key?("retained_candidates")
      retained = value["retained_candidates"]
      if retained.is_a?(Hash)
        retained.each.with_index do |(key, candidate), index|
          info = candidate_info(candidate, "retained-#{index}")
          info["map_key_matches_digest"] = candidate.is_a?(Hash) && key == candidate["digest"]
          result["candidates"] << info
        end
        result["additional_count"] = retained.size
      else
        result["warnings"] << "retained_candidates_not_map; preserved_opaque"
      end
    end
    result["snapshot_count"] = result["candidates"].size
    result["warnings"] << "unknown_fields_preserved" if result["unknown_root_fields"].positive?
    result["warnings"] << "unrecognized_root_preserved_opaque" if result["snapshot_count"].zero?
    result["warnings"] << "candidate_requires_review" if result["candidates"].any? { |c| c["digest_status"] != "match" || c["declared_valid"] != true || c["source"] != "p1.1-cookie" }
    result["warnings"] << "aggregate_digest_mismatch" if result["aggregate_digest_status"] == "mismatch"
    result["warnings"] << "retained_key_mismatch" if result["candidates"].any? { |c| c["map_key_matches_digest"] == false }
    result
  rescue Invalid
    result["blockers"] << "backup_json_incompatible; original_retained_in_database"
    result
  end

  def export(destination:, user_id: 1)
    captured = capture(user_id: user_id)
    summary = inventory(captured)
    raise Invalid, "Exportação bloqueada por estrutura incompatível" unless summary.fetch("blockers").empty?
    content = { "format" => FORMAT, "version" => VERSION, "artifact_id" => SecureRandom.uuid,
      "exported_at" => Time.now.utc.iso8601(6), "historical_candidate_dates" => "unknown",
      "capture" => captured, "inventory" => summary,
      "backup_sha256" => original(captured) && Digest::SHA256.hexdigest(original(captured)) }
    envelope = { "content" => content, "content_sha256" => checksum(content) }
    destination = destination_path(destination)
    temporary = File.join(File.dirname(destination), ".accio-#{SecureRandom.hex(16)}.tmp")
    begin
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
        file.write(JSON.generate(envelope))
        file.flush
        file.fsync
      end
      verify(temporary)
      # Atomic no-clobber publication on the same filesystem; rename would overwrite.
      File.link(temporary, destination)
      File.unlink(temporary)
      File.open(File.dirname(destination), File::RDONLY, &:fsync)
      verify(destination)
    rescue SystemCallError, IOError
      raise Invalid, "Exportação não confirmada; confira o destino privado antes de tentar novamente"
    ensure
      File.unlink(temporary) if temporary && File.exist?(temporary)
    end
  end

  # Returns private content to a caller, never prints it. CLI prints only inventory metadata.
  def verify(path)
    path = private_file(path)
    envelope = parse(read_private(path))
    raise Invalid, "Envelope incompatível" unless envelope.is_a?(Hash) && envelope.keys.sort == %w[content content_sha256]
    content = envelope.fetch("content")
    unless content.is_a?(Hash) && content["format"] == FORMAT && content["version"] == VERSION &&
        envelope["content_sha256"] == checksum(content)
      raise Invalid, "Formato ou hash da exportação incompatível"
    end
    capture = content.fetch("capture")
    validate_capture!(capture)
    raw = original(capture)
    unless content["backup_sha256"] == (raw && Digest::SHA256.hexdigest(raw)) &&
        content["inventory"] == inventory(capture) && content["inventory"].fetch("blockers").empty?
      raise Invalid, "Conteúdo ou manifesto inconsistente"
    end
    content
  rescue SystemCallError, JSON::ParserError, KeyError, TypeError, ArgumentError
    raise Invalid, "Arquivo de exportação inválido ou indisponível"
  end

  def original(capture)
    encoded = capture.fetch("backup_base64")
    encoded && Base64.strict_decode64(encoded).force_encoding(Encoding::UTF_8)
  rescue KeyError, ArgumentError, TypeError
    raise Invalid, "Representação original incompatível"
  end

  private

  def parse(bytes)
    text = bytes.dup.force_encoding(Encoding::UTF_8)
    raise Invalid, "Codificação incompatível" unless text.valid_encoding?
    JSON.parse(text, allow_duplicate_key: false)
  rescue JSON::ParserError
    raise Invalid, "JSON incompatível"
  end

  def checksum(content)
    Digest::SHA256.hexdigest(JSON.generate(content))
  end

  def candidate_info(value, location)
    return { "location" => location, "type" => "incompatible", "digest_status" => "unverifiable", "declared_valid" => nil, "source" => "unknown" } unless value.is_a?(Hash)
    raw = value["raw"]
    digest = value["digest"]
    status = if raw.is_a?(String) && digest.is_a?(String) && digest.match?(/\A[0-9a-f]{64}\z/)
      Digest::SHA256.hexdigest(raw) == digest ? "match" : "mismatch"
    else
      "unverifiable"
    end
    { "location" => location, "type" => "candidate", "raw_present" => value.key?("raw"), "raw_string" => raw.is_a?(String),
      "value_present" => value.key?("value"), "declared_valid" => [ true, false ].include?(value["valid"]) ? value["valid"] : nil,
      "source" => value["source"] == "p1.1-cookie" ? "p1.1-cookie" : "unknown",
      "source_present" => value.key?("source"), "digest_status" => status,
      "unknown_fields" => (value.keys - CANDIDATE_KEYS - [ "retained_candidates" ]).size }
  end

  def validate_capture!(capture)
    unless capture.is_a?(Hash) && capture.keys.sort == %w[backup_base64 record]
      raise Invalid, "Captura incompatível"
    end
    record = capture["record"]
    unless record.nil? || (record.is_a?(Hash) && record.keys.sort == METADATA.sort && record["lock_version"].is_a?(Integer))
      raise Invalid, "Metadados incompatíveis"
    end
    raise Invalid, "Snapshot sem agregado" if record.nil? && capture["backup_base64"]
  end

  def private_directory(path)
    expanded = File.expand_path(path)
    real = File.realpath(expanded)
    stat = File.stat(real)
    unless real == expanded && stat.directory? && stat.uid == Process.uid && (stat.mode & 0o077).zero? &&
        real != @checkout && !real.start_with?(@checkout + File::SEPARATOR)
      raise Invalid, "Use diretório privado, sem symlinks, fora do checkout"
    end
    real
  end

  def read_private(path)
    File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
      stat = file.stat
      unless stat.file? && stat.uid == Process.uid && (stat.mode & 0o077).zero? && stat.nlink == 1
        raise Invalid, "Arquivo privado incompatível"
      end
      file.read
    end
  end

  def private_file(path)
    raise Invalid, "Caminho explícito obrigatório" unless path.is_a?(String) && !path.empty?
    expanded = File.expand_path(path)
    private_directory(File.dirname(expanded))
    stat = File.lstat(expanded)
    unless stat.file? && !stat.symlink? && stat.uid == Process.uid && (stat.mode & 0o077).zero? && stat.nlink == 1
      raise Invalid, "Arquivo deve ser privado, regular e sem links"
    end
    expanded
  end

  def destination_path(path)
    raise Invalid, "Destino explícito obrigatório" unless path.is_a?(String) && !path.empty?
    expanded = File.expand_path(path)
    private_directory(File.dirname(expanded))
    unless File.basename(expanded).match?(/\A[a-zA-Z0-9][a-zA-Z0-9._-]*\.json\z/)
      raise Invalid, "Use nome de artefato JSON explícito"
    end
    raise Invalid, "Destino existente; nenhuma sobrescrita permitida" if File.exist?(expanded) || File.symlink?(expanded)
    expanded
  end
end
