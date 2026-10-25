module Vault
  class Configuration
    DEFAULT_LIMITS = {
      document_bytes: 2_097_152, depth: 8, path_bytes: 4096, component_bytes: 255,
      entries: 10_000, operation_bytes: 32 * 1024 * 1024, seconds: 5.0
    }.freeze

    attr_reader :path, :limits, :protected_paths, :clock

    def self.from_env(environment = ENV, protected_paths: [], **legacy_environment)
      # Ruby 3 treats the existing from_env("KEY" => "value") form as keywords
      # once this factory accepts a keyword. Keep that environment-hash API.
      unless legacy_environment.empty?
        raise ArgumentError, "pass one environment hash" unless environment.equal?(ENV) && legacy_environment.keys.all?(String)
        environment = legacy_environment
      end
      new(path: environment["ACCIO_VAULT_PATH"], protected_paths: protected_paths)
    end

    def initialize(path: nil, limits: {}, protected_paths: [], clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @path = path.is_a?(String) ? path.dup.freeze : path
      @clock = clock
      @limits = DEFAULT_LIMITS.merge(limits.is_a?(Hash) ? limits : {}).freeze
      @valid = limits.is_a?(Hash) && (limits.keys - DEFAULT_LIMITS.keys).empty? &&
        @limits.all? { |key, value| valid_limit?(key, value) } &&
        clock.respond_to?(:call) &&
        protected_paths.is_a?(Array) && protected_paths.all? { |item| item.is_a?(String) && item.start_with?("/") && !item.include?("\0") }
      @protected_paths = @valid ? protected_paths.map { |item| item.dup.freeze }.freeze : [].freeze
      freeze
    end

    def configured?
      !path.nil? && path != ""
    end

    def valid?
      @valid && (!configured? || path.is_a?(String))
    end

    def budget
      Budget.new(self)
    end

    private

    def valid_limit?(key, value)
      if key == :seconds
        value.is_a?(Numeric) && value.real? && value.finite? && value.positive? && value <= DEFAULT_LIMITS.fetch(key)
      else
        value.is_a?(Integer) && value >= (key == :depth ? 0 : 1) && value <= DEFAULT_LIMITS.fetch(key)
      end
    end

    # An operation-local budget. Do not share it between concurrent operations.
    class Budget
      attr_reader :bytes_read

      def initialize(configuration)
        @configuration = configuration
        @started = configuration.clock.call
        @bytes_read = 0
      end

      def check!
        raise LinuxFilesystem::Error.new(:timed_out) if elapsed >= @configuration.limits.fetch(:seconds)
      end

      def remaining_bytes
        @configuration.limits.fetch(:operation_bytes) - bytes_read
      end

      def consume!(count)
        @bytes_read += count
        raise LinuxFilesystem::Error.new(:limit_exceeded) if remaining_bytes.negative?
        check!
      end

      def elapsed
        @configuration.clock.call - @started
      end

      def metrics
        { bytes_read: bytes_read, seconds: elapsed }
      end
    end
  end
end
