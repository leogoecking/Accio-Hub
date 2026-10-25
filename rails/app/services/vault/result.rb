module Vault
  class Result
    attr_reader :state, :code, :data, :metrics

    def initialize(state:, code: nil, data: {}, metrics: {})
      @state, @code = state, code
      @data, @metrics = immutable(data), immutable(metrics)
      freeze
    end

    def success?
      [ :ready, :complete ].include?(state)
    end

    def self.failure(error, root: false, metrics: {})
      state = case error.code
      when :invalid_root then :invalid_configuration
      when :unsupported_platform, :unsupported_filesystem then :unsupported_platform
      when :changed then :changed
      when :limit_exceeded, :timed_out then :limit_exceeded
      when :invalid_path, :blocked_resolution, :symlink, :hardlink, :special_file then :blocked
      when :procfs_unavailable, :resource_exhausted, :io_error then :unavailable
      when :not_found then :unavailable
      when :unreadable then root ? :unavailable : :unreadable
      else :unavailable # Unknown codes are failures, not permission diagnoses.
      end
      new(state: state, code: error.code, metrics: metrics)
    end

    def self.metadata(stat)
      { type: stat.ftype, size: stat.size, device: stat.dev, inode: stat.ino,
        links: stat.nlink, mode: stat.mode, mtime: stat.mtime, ctime: stat.ctime }
    end

    private

    def immutable(value)
      case value
      when Hash then value.to_h { |key, item| [ immutable(key), immutable(item) ] }.freeze
      when Array then value.map { |item| immutable(item) }.freeze
      when String, Time then value.dup.freeze
      else value.freeze
      end
    end
  end
end
