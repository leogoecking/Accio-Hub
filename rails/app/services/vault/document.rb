require "digest"
require_relative "result"
require_relative "path_policy"
require_relative "configuration"
require_relative "metadata"

module Vault
  class Document
    IDENTITY_STATES = [ :not_applicable, :unverified, :unique_in_observation, :conflicting ].freeze
    attr_reader :kind, :source_read_result, :source_read_state, :source_read_code, :path,
      :raw_bytes, :source_sha256, :raw_header, :raw_body, :ranges, :local_classification,
      :classification, :parse_status, :metadata, :claimed_id, :identity_status, :diagnostics, :metrics
    alias_method :read_state, :source_read_state

    def self.from_bytes(bytes, kind: :note, **options)
      raise ArgumentError, "bytes must be a String" unless bytes.is_a?(String)
      result = Result.new(state: :complete, data: { bytes: bytes.b, sha256: Digest::SHA256.hexdigest(bytes),
        path: kind == :folder ? ".accio-folder.yml" : "synthetic.md" })
      from_read_result(result, kind: kind, **options)
    end

    def self.from_read_result(read_result, kind:, parser_limits: Metadata::Limits.new, budget: nil, clock: Metadata::Guard::CLOCK)
      new(read_result, kind, parser_limits, budget, clock)
    end

    def valid_metadata?
      local_classification == :managed && parse_status == :valid && !metadata.nil?
    end

    def present_fields
      metadata ? metadata.present_fields : [].freeze
    end

    def with_identity(status, diagnostics: [])
      raise ArgumentError, "unknown identity state" unless IDENTITY_STATES.include?(status)
      copy = dup
      copy.instance_variable_set(:@identity_status, status)
      copy.instance_variable_set(:@classification, status == :conflicting ? :identity_conflict : local_classification)
      collector = Metadata::Diagnostics.new(@diagnostic_limit)
      (self.diagnostics + diagnostics).each do |item|
        collector.add(item.fetch(:code), severity: item.fetch(:severity), domain: item.fetch(:domain), field: item[:field])
      end
      copy.instance_variable_set(:@diagnostics, collector.items)
      copy.freeze
    end

    private

    def initialize(read_result, kind, limits, budget, clock)
      raise ArgumentError, "unsupported document kind" unless [ :note, :folder ].include?(kind)
      @kind, @source_read_result = kind, read_result
      @diagnostic_limit = limits[:diagnostics]
      @source_read_state, @source_read_code = read_result.state, read_result.code
      @parse_status, @identity_status, @ranges = :not_attempted, :not_applicable, {}.freeze
      @diagnostics, @metrics = [].freeze, read_result.metrics
      if read_result.state == :complete
        validate_read!(read_result)
        interpret!(limits, budget, clock)
      else
        @diagnostics = Metadata.immutable([ { code: read_result.code || read_result.state, severity: :error, domain: :read } ])
      end
      freeze
    end

    def validate_read!(result)
      bytes = result.data.fetch(:bytes)
      sha = result.data.fetch(:sha256)
      raise ArgumentError, "invalid read payload" unless bytes.is_a?(String) && bytes.encoding == Encoding::BINARY &&
        sha == Digest::SHA256.hexdigest(bytes)
      policy = PathPolicy.new(Configuration.new)
      @path = policy.validate(result.data.fetch(:path)).dup.freeze
      expected = kind == :note ? :markdown : :marker
      raise ArgumentError, "read kind/path mismatch" unless policy.candidate(path) == expected
      @raw_bytes, @source_sha256 = bytes.dup.freeze, sha.dup.freeze
    end

    def interpret!(limits, budget, clock)
      guard = Metadata::Guard.new(limits, budget: budget, clock: clock)
      guard.check!
      guard.limit!(:document_limit, domain: :framing) if raw_bytes.bytesize > limits[:document_bytes]
      utf8 = raw_bytes.dup.force_encoding(Encoding::UTF_8)
      unless utf8.valid_encoding?
        raise Metadata::Rejected.new(:invalid_utf8, status: :incompatible, domain: :framing)
      end
      yaml = frame!(guard)
      if yaml
        parsed = Metadata.parse(yaml, kind: kind, parser_limits: limits, guard: guard)
        @parse_status, @metadata, @claimed_id = parsed.status, parsed.metadata, parsed.claimed_id
        @diagnostics, @metrics = parsed.diagnostics, Metadata.immutable(source_read_result.metrics.merge(parsed.metrics))
      else
        @parse_status = :unmanaged
      end
      @local_classification = case parse_status
      when :valid then :managed
      when :limit_exceeded then :incompatible
      else parse_status
      end
      @classification = @local_classification
      @identity_status = valid_metadata? ? :unverified : :not_applicable
      guard.check!
    rescue Metadata::Rejected => error
      reject!(error)
    rescue LinuxFilesystem::Error => error
      raise unless [ :timed_out, :limit_exceeded ].include?(error.code)
      reject!(Metadata::Rejected.new(error.code == :timed_out ? :parse_timeout : :operation_limit,
        status: :limit_exceeded, domain: :read))
    end

    def reject!(error)
      @parse_status = error.status
      @local_classification = @classification = error.status == :limit_exceeded ? :incompatible : error.status
      @metadata = @claimed_id = nil
      @identity_status = :not_applicable
      @diagnostics = Metadata.immutable([ { code: error.code, severity: :error, domain: error.domain } ])
    end

    def frame!(guard)
      bom_size = raw_bytes.start_with?("\xEF\xBB\xBF".b) ? 3 : 0
      if kind == :folder
        guard.limit!(:header_limit, domain: :framing) if raw_bytes.bytesize > guard.limits[:header_bytes]
        set_ranges!(bom_size, bom_size, raw_bytes.bytesize, raw_bytes.bytesize)
        return raw_bytes.byteslice(bom_size..).dup.force_encoding(Encoding::UTF_8)
      end
      opening = if raw_bytes.byteslice(bom_size, 5) == "---\r\n".b then 5
      elsif raw_bytes.byteslice(bom_size, 4) == "---\n".b then 4
      end
      if !opening && raw_bytes.byteslice(bom_size, 4) == "---\r".b
        raise Metadata::Rejected.new(:unsupported_line_ending, status: :incompatible, domain: :framing)
      end
      unless opening
        set_ranges!(bom_size, bom_size, bom_size, bom_size)
        return nil
      end
      yaml_start = cursor = bom_size + opening
      loop do
        guard.check!
        guard.limit!(:header_limit, domain: :framing) if cursor > guard.limits[:header_bytes]
        newline = raw_bytes.index("\n".b, cursor)
        finish = newline ? newline + 1 : raw_bytes.bytesize
        # No bytes beyond the budget are parsed, even if the next LF is in the body.
        guard.limit!(:header_limit, domain: :framing) if finish > guard.limits[:header_bytes]
        line = raw_bytes.byteslice(cursor, finish - cursor)
        if [ "---\n".b, "---\r\n".b, "---".b ].include?(line)
          set_ranges!(bom_size, yaml_start, cursor, finish)
          return raw_bytes.byteslice(yaml_start, cursor - yaml_start).dup.force_encoding(Encoding::UTF_8)
        end
        if /\r(?!\n)/.match?(line)
          raise Metadata::Rejected.new(:unsupported_line_ending, status: :incompatible, domain: :framing)
        end
        raise Metadata::Rejected.new(:unclosed_frontmatter, domain: :framing) unless newline
        cursor = finish
      end
    end

    def set_ranges!(bom_size, yaml_start, yaml_end, body_start)
      @ranges = Metadata.immutable({ bom: (0...bom_size), yaml: (yaml_start...yaml_end), body: (body_start...raw_bytes.bytesize) })
      @raw_header = raw_bytes.byteslice(0, body_start).freeze
      @raw_body = raw_bytes.byteslice(body_start..).freeze
    end
  end
end
