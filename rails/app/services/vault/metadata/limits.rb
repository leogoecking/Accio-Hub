module Vault
  class Metadata
    # Separate from Configuration 01: only reductions are accepted.
    class Limits
      DEFAULTS = { document_bytes: 2_097_152, header_bytes: 65_536, lines: 2048,
        nodes: 4096, depth: 16, mapping: 256, sequence: 512, scalar_bytes: 8192,
        schema_digits: 19, id_bytes: 4096, key_bytes: 128, tag_bytes: 256,
        label_bytes: 1024, tags: 128, references: 256, bindings: 256,
        diagnostics: 32, seconds: 0.1, identity_bytes: 8 * 1024 * 1024, entries: 10_000 }.freeze

      def initialize(**reductions)
        raise ArgumentError, "unknown parser limit" unless (reductions.keys - DEFAULTS.keys).empty?
        @values = DEFAULTS.merge(reductions)
        @values.each do |key, value|
          valid = key == :seconds ? value.is_a?(Numeric) && value.real? && value.finite? : value.is_a?(Integer)
          raise ArgumentError, "invalid parser limit" unless valid && value.positive? && value <= DEFAULTS.fetch(key)
        end
        @values.freeze
        freeze
      end

      def [](key)
        @values.fetch(key)
      end
    end

    def self.immutable(value)
      case value
      when Hash then value.to_h { |key, item| [ immutable(key), immutable(item) ] }.freeze
      when Array then value.map { |item| immutable(item) }.freeze
      when String then value.dup.freeze
      else value.freeze
      end
    end

    class Rejected < StandardError
      attr_reader :code, :status, :domain, :field

      def initialize(code, status: :invalid, domain: :yaml, field: nil)
        @code, @status, @domain, @field = code, status, domain, field
        super(code.to_s)
      end
    end

    # Contents, extra keys and Psych messages never enter diagnostics.
    class Diagnostics
      def initialize(limits)
        @limit = limits.is_a?(Integer) ? limits : limits[:diagnostics]
        @items = []
      end

      def add(code, severity: :warning, domain: :metadata, field: nil)
        item = { code: code, severity: severity, domain: domain }
        item[:field] = field if field
        if @items.size < @limit
          @items << item
        else
          # Preserve evidence of failure even after a flood of warnings.
          @items[0] = item if severity == :error
          if @limit > 1 || @items.first[:severity] != :error
            @items[-1] = { code: :diagnostics_truncated, severity: :warning, domain: domain }
          end
        end
      end

      def failure(error)
        add(error.code, severity: :error, domain: error.domain, field: error.field)
      end

      def items
        Metadata.immutable(@items)
      end
    end

    class Guard
      CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      attr_reader :limits

      def initialize(limits, clock: CLOCK, budget: nil)
        @limits, @clock, @budget = limits, clock, budget
        @started = clock.call
      end

      def check!
        limit!(:parse_timeout) if @clock.call - @started >= limits[:seconds]
        begin
          @budget&.check!
        rescue StandardError => error
          raise unless defined?(LinuxFilesystem::Error) && error.is_a?(LinuxFilesystem::Error) &&
            [ :timed_out, :limit_exceeded ].include?(error.code)
          limit!(error.code == :timed_out ? :parse_timeout : :operation_limit, domain: :read)
        end
      end

      def limit!(code, domain: :yaml)
        raise Rejected.new(code, status: :limit_exceeded, domain: domain)
      end

      def precheck!(yaml)
        check!
        limit!(:header_limit) if yaml.bytesize > limits[:header_bytes]
        limit!(:line_limit) if yaml.count("\n") > limits[:lines]
        raise Rejected.new(:invalid_utf8, status: :incompatible) unless yaml.dup.force_encoding(Encoding::UTF_8).valid_encoding?
        raise Rejected.new(:unsupported_line_ending, status: :incompatible) if /\r(?!\n)/.match?(yaml)
      end
    end
  end
end
