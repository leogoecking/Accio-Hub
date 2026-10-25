require_relative "configuration"
require_relative "result"
require_relative "linux_filesystem"

module Vault
  class Root
    attr_reader :configuration

    def initialize(configuration = Configuration.new, filesystem: LinuxFilesystem.new)
      @configuration, @filesystem = configuration, filesystem
    end

    def status
      return Result.new(state: :invalid_configuration, code: :invalid_configuration) unless configuration.valid?
      Result.new(state: :unconfigured) unless configuration.configured?
    end

    def call
      with_session { |_session| Result.new(state: :ready) }
    end

    def with_session
      initial = status
      return initial if initial
      @filesystem.with_root(configuration.path, protected_paths: configuration.protected_paths) do |session|
        yield session
      rescue LinuxFilesystem::Error => error
        # A consumer failure is operation-scoped. Returning its failure result
        # also lets the filesystem finish its root postcheck before returning.
        Result.failure(error)
      end
    rescue LinuxFilesystem::Error => error
      # Only acquisition and postcheck failures belong to the root boundary.
      Result.failure(error, root: true)
    end
  end
end
