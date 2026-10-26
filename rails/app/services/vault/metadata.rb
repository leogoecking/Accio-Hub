require "date"
require_relative "metadata/yaml_parser"

module Vault
  class Metadata
    NOTE_FIELDS = %w[accio_schema id title tags project_ids task_ids favorite collection link_bindings created_at updated_at].freeze
    FOLDER_FIELDS = %w[accio_schema id].freeze
    Scalar = Data.define(:type, :value)
    Outcome = Data.define(:status, :metadata, :claimed_id, :diagnostics, :metrics)
    attr_reader :fields, :extensions, :present_fields

    def initialize(fields, extensions)
      @fields, @extensions = self.class.immutable(fields), self.class.immutable(extensions)
      @present_fields = fields.keys.map { |key| key.dup.freeze }.freeze
      freeze
    end

    def self.parse(yaml, kind:, parser_limits: Limits.new, guard: nil, clock: Guard::CLOCK, budget: nil)
      guard ||= Guard.new(parser_limits, clock: clock, budget: budget)
      validator = Validator.new(kind, guard)
      validator.call(yaml)
    end

    class Validator
      def initialize(kind, guard)
        raise ArgumentError, "unsupported document kind" unless [ :note, :folder ].include?(kind)
        @kind, @guard, @limits = kind, guard, guard.limits
        @diagnostics = Diagnostics.new(@limits)
        @parser = YamlParser.new(guard)
        @claim = nil
      end

      def call(yaml)
        root = @parser.call(yaml)
        mapping = @parser.maps.fetch(root)
        unless mapping.key?("accio_schema")
          fail!(:missing_field, field: "accio_schema") if @kind == :folder
          return outcome(:unmanaged)
        end
        schema = schema!(mapping.fetch("accio_schema"))
        # Only after the WHOLE syntax/policy inspection can claims be extracted.
        candidate = mapping["id"]
        @claim = candidate.value if valid_id_node?(candidate)
        fail!(:unsupported_schema, status: :incompatible) unless schema == 1
        fail!(:missing_field, field: "id") unless candidate
        fields = { "accio_schema" => schema, "id" => id!(candidate, "id") }
        known = @kind == :note ? NOTE_FIELDS : FOLDER_FIELDS
        mapping.each do |name, node|
          @guard.check!
          next if [ "accio_schema", "id" ].include?(name)
          fields[name] = field!(name, node) if known.include?(name)
        end
        dates!(fields)
        extensions = mapping.reject { |name, _| known.include?(name) }.to_h do |name, node|
          @diagnostics.add(:unknown_field)
          [ name, opaque(node) ]
        end
        metadata = Metadata.new(fields, extensions)
        @guard.check!
        outcome(:valid, metadata)
      rescue Rejected => error
        @claim = nil if error.status == :limit_exceeded
        @diagnostics.failure(error)
        outcome(error.status)
      rescue Psych::SyntaxError
        @claim = nil
        @diagnostics.add(:yaml_syntax, severity: :error, domain: :yaml)
        outcome(:invalid)
      end

      private

      def outcome(status, metadata = nil)
        Outcome.new(status, metadata, @claim&.dup&.freeze, @diagnostics.items, @parser.metrics).freeze
      end

      def fail!(code, status: :invalid, field: nil)
        raise Rejected.new(code, status: status, domain: :metadata, field: field)
      end

      def schema!(node)
        fail!(:wrong_type, field: "accio_schema") unless node.is_a?(Psych::Nodes::Scalar) && Metadata.scalar_type(node) == :int
        value = node.value
        fail!(:unsupported_scalar_form, field: "accio_schema") unless /\A(?:0|-?[1-9][0-9]*)\z/.match?(value)
        @guard.limit!(:schema_limit) if value.delete_prefix("-").bytesize > @limits[:schema_digits]
        value.to_i
      end

      def string!(node, field)
        fail!(:wrong_type, field: field) unless node.is_a?(Psych::Nodes::Scalar) && Metadata.scalar_type(node) == :string
        node.value
      end

      def valid_id_node?(node)
        node.is_a?(Psych::Nodes::Scalar) && Metadata.scalar_type(node) == :string &&
          node.value.valid_encoding? && !node.value.include?("\0") &&
          !/\A[[:space:]]*\z/.match?(node.value) && node.value.bytesize <= @limits[:id_bytes]
      end

      def id!(node, field)
        value = string!(node, field)
        @guard.limit!(:id_limit) if value.bytesize > @limits[:id_bytes]
        fail!(:invalid_id, field: field) if value.include?("\0") || /\A[[:space:]]*\z/.match?(value)
        value
      end

      def text!(node, field, max:, limit_code:, line: false)
        value = string!(node, field)
        @guard.limit!(limit_code) if value.bytesize > max
        fail!(:wrong_type, field: field) if /\A[[:space:]]*\z/.match?(value) || /\p{Cc}/.match?(value) ||
          (line && /[\r\n\u0085\u2028\u2029]/.match?(value))
        value
      end

      def list!(node, field, max:)
        fail!(:wrong_type, field: field) unless node.is_a?(Psych::Nodes::Sequence)
        @guard.limit!(:sequence_limit) if node.children.size > max
        node.children
      end

      def field!(name, node)
        case name
        when "title"
          value = string!(node, name)
          @diagnostics.add(:legacy_title, field: name) if /\A[[:space:]]*\z/.match?(value) || value.encode(Encoding::UTF_16LE).bytesize / 2 > 120
          value
        when "tags", "project_ids", "task_ids"
          list = list!(node, name, max: @limits[name == "tags" ? :tags : :references]).map do |item|
            name == "tags" ? text!(item, name, max: @limits[:tag_bytes], limit_code: :tag_limit) : id!(item, name)
          end
          if list.uniq.size != list.size
            name == "tags" ? @diagnostics.add(:duplicate_tag, field: name) : fail!(:duplicate_value, field: name)
          end
          list
        when "favorite"
          fail!(:wrong_type, field: name) unless node.is_a?(Psych::Nodes::Scalar) && Metadata.scalar_type(node) == :bool
          fail!(:unsupported_scalar_form, field: name) unless %w[true false].include?(node.value)
          node.value == "true"
        when "collection"
          value = string!(node, name)
          fail!(:invalid_enum, field: name) unless %w[notes capture journal].include?(value)
          value
        when "created_at", "updated_at"
          return nil if node.is_a?(Psych::Nodes::Scalar) && Metadata.scalar_type(node) == :null
          value = string!(node, name)
          instant!(value, name)
          value
        when "link_bindings"
          bindings!(node)
        end
      end

      def bindings!(node)
        seen = {}
        list!(node, "link_bindings", max: @limits[:bindings]).map do |binding|
          fail!(:wrong_type, field: "link_bindings") unless binding.is_a?(Psych::Nodes::Mapping)
          map = @parser.maps.fetch(binding)
          %w[label target_id].each { |name| fail!(:missing_field, field: name) unless map.key?(name) }
          label = text!(map.fetch("label"), "label", max: @limits[:label_bytes], limit_code: :label_limit, line: true)
          fail!(:duplicate_binding, field: "label") if seen[label]
          seen[label] = true
          result = { "label" => label, "target_id" => id!(map.fetch("target_id"), "target_id") }
          map.each do |name, value|
            next if result.key?(name)
            @diagnostics.add(:unknown_field)
            result[name] = opaque(value)
          end
          result
        end
      end

      def instant!(value, field)
        match = /\A([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]{1,9}))?(Z|[+-][0-9]{2}:[0-9]{2})\z/.match(value)
        fail!(:invalid_date, field: field) unless match
        year, month, day, hour, minute, second = match.captures.first(6).map(&:to_i)
        zone = match[8]
        offset_hour, offset_minute = zone == "Z" ? [ 0, 0 ] : [ zone[1, 2].to_i, zone[4, 2].to_i ]
        valid = year.between?(1, 9999) && Date.valid_date?(year, month, day, Date::GREGORIAN) && hour < 24 && minute < 60 && second < 60 &&
          offset_hour <= 14 && offset_minute < 60 && (offset_hour < 14 || offset_minute.zero?) && zone != "-00:00"
        fail!(:invalid_date, field: field) unless valid
        offset = (offset_hour * 3600 + offset_minute * 60) * (zone.start_with?("-") ? -1 : 1)
        fraction = match[7] ? Rational(match[7].to_i, 10 ** match[7].size) : 0
        Date.new(year, month, day, Date::GREGORIAN).jd * 86400 + hour * 3600 + minute * 60 + second - offset + fraction
      end

      def dates!(fields)
        if fields["created_at"] && fields["updated_at"] && instant!(fields["updated_at"], "updated_at") < instant!(fields["created_at"], "created_at")
          @diagnostics.add(:date_order_anomaly)
        end
      end

      def opaque(node)
        @guard.check!
        case node
        when Psych::Nodes::Mapping then @parser.maps.fetch(node).to_h { |key, value| [ key, opaque(value) ] }
        when Psych::Nodes::Sequence then node.children.map { |child| opaque(child) }
        else Scalar.new(Metadata.scalar_type(node), node.value.dup.freeze).freeze
        end
      end
    end
  end
end
