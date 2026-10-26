require "json"
require_relative "document"

module Vault
  class Serializer
    Result = Data.define(:bytes, :diagnostics, :source_sha256, :identity_status) do
      def accepted?
        !bytes.nil?
      end
    end

    def initialize(parser_limits: Metadata::Limits.new)
      @limits = parser_limits
      freeze
    end

    def original(document)
      return failure(:unsupported_edit) unless document.raw_bytes
      result(document.raw_bytes, document)
    end

    def replace_body(document, replacement_bytes)
      allowed = document.kind == :note && document.read_state == :complete && document.valid_metadata? &&
        document.parse_status == :valid && [ :unverified, :unique_in_observation ].include?(document.identity_status)
      return failure(:unsupported_edit) unless allowed
      return failure(:wrong_type) unless replacement_bytes.is_a?(String)
      return failure(:document_limit) if document.raw_header.bytesize + replacement_bytes.bytesize > @limits[:document_bytes]
      body = body_bytes(replacement_bytes)
      return failure(:invalid_utf8) unless body
      return failure(:ambiguous_body_boundary) if !body.empty? && !document.raw_header.end_with?("\n".b)
      result(document.raw_header + body, document)
    end

    def update_properties(*)
      failure(:unsupported_edit)
    end

    # Deliberately small deterministic emitter for NEW primitives only. All strings
    # are quoted (JSON double quotes are a YAML subset); no loader/dump of an origin.
    def compose_new(metadata:, body:, kind: :note)
      return failure(:wrong_type) unless metadata.is_a?(Hash) && [ :note, :folder ].include?(kind)
      return failure(:wrong_type) unless primitive_input?(metadata)
      fields = Metadata.immutable(metadata)
      return failure(:missing_field) unless fields.key?("id")
      return failure(:wrong_type) if fields.key?("accio_schema") && fields["accio_schema"] != 1
      fields = { "accio_schema" => 1 }.merge(fields)
      if kind == :note
        title = fields["title"]
        return failure(:missing_field) unless fields.key?("title")
        return failure(:wrong_type) unless title.is_a?(String) && !/\A[[:space:]]*\z/.match?(title) && title.encode(Encoding::UTF_16LE).bytesize / 2 <= 120
        fields = { "tags" => [], "project_ids" => [], "task_ids" => [], "favorite" => false,
          "collection" => "notes", "link_bindings" => [] }.merge(fields)
      end
      return failure(:wrong_type) unless body.is_a?(String)
      return failure(:document_limit) if body.bytesize > @limits[:document_bytes]
      bytes = body_bytes(body)
      return failure(:invalid_utf8) unless bytes
      return failure(:unsupported_edit) if kind == :folder && !bytes.empty?
      yaml = emit(fields)
      raw = kind == :note ? "---\n#{yaml}\n---\n".b + bytes : "#{yaml}\n".b
      document = Document.from_bytes(raw, kind: kind, parser_limits: @limits)
      return Result.new(nil, document.diagnostics, nil, :not_applicable).freeze unless document.valid_metadata?
      interpreted = document.metadata.fields.merge(document.metadata.extensions)
      return failure(:unsupported_edit) unless equivalent?(fields, interpreted) && document.raw_body == bytes
      result(raw, document, source_sha256: nil)
    rescue Metadata::Rejected => error
      failure(error.code)
    end

    private

    def primitive_input?(value, depth = 0, counter = [ 0, 0 ])
      counter[0] += 1
      raise Metadata::Rejected.new(:node_limit) if counter[0] > @limits[:nodes]
      raise Metadata::Rejected.new(:depth_limit) if depth > @limits[:depth]
      case value
      when String
        counter[1] += value.bytesize
        raise Metadata::Rejected.new(:header_limit) if counter[1] > @limits[:header_bytes]
        value.encoding == Encoding::UTF_8 && value.valid_encoding? && value.bytesize <= @limits[:scalar_bytes]
      when Hash then value.size <= @limits[:mapping] && value.all? { |key, item| key.is_a?(String) && primitive_input?(key, depth + 1, counter) && primitive_input?(item, depth + 1, counter) }
      when Array then value.size <= @limits[:sequence] && value.all? { |item| primitive_input?(item, depth + 1, counter) }
      when Integer then value.between?(-9_223_372_036_854_775_808, 9_223_372_036_854_775_807)
      when TrueClass, FalseClass, NilClass then true
      else false
      end
    end

    def emit(value, output = +"")
      case value
      when Hash
        append!(output, "{")
        value.each_with_index do |(key, item), index|
          append!(output, ", ") unless index.zero?
          append!(output, quoted(key))
          append!(output, ": ")
          emit(item, output)
        end
        append!(output, "}")
      when Array
        append!(output, "[")
        value.each_with_index do |item, index|
          append!(output, ", ") unless index.zero?
          emit(item, output)
        end
        append!(output, "]")
      else append!(output, value.is_a?(String) ? quoted(value) : JSON.generate(value))
      end
      output
    end

    def quoted(value)
      # libyaml folds a literal NEL in double quotes. Escapes preserve values.
      JSON.generate(value).gsub("\u0085", '\\u0085').gsub("\u2028", '\\u2028').gsub("\u2029", '\\u2029')
    end

    def equivalent?(expected, actual)
      if actual.is_a?(Metadata::Scalar)
        type, value = case expected
        when String then [ :string, expected ]
        when Integer then [ :int, expected.to_s ]
        when TrueClass, FalseClass then [ :bool, expected ? "true" : "false" ]
        when NilClass then [ :null, "null" ]
        else return false
        end
        return actual.type == type && actual.value == value
      end
      return false unless expected.class == actual.class
      case expected
      when Hash then expected.size == actual.size && expected.all? { |key, value| actual.key?(key) && equivalent?(value, actual[key]) }
      when Array then expected.size == actual.size && expected.zip(actual).all? { |left, right| equivalent?(left, right) }
      else expected == actual
      end
    end

    def append!(output, piece)
      raise Metadata::Rejected.new(:header_limit) if output.bytesize + piece.bytesize > @limits[:header_bytes]
      output << piece
    end

    def body_bytes(value)
      return nil unless value.is_a?(String)
      bytes = value.b
      bytes if bytes.dup.force_encoding(Encoding::UTF_8).valid_encoding?
    end

    def result(bytes, document, source_sha256: document.source_sha256)
      Result.new(bytes.b.freeze, document.diagnostics, source_sha256, document.identity_status).freeze
    end

    def failure(code)
      Result.new(nil, Metadata.immutable([ { code: code, severity: :error, domain: :serialization } ]), nil, :not_applicable).freeze
    end
  end
end
