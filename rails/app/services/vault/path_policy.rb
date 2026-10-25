require_relative "linux_filesystem"

module Vault
  class PathPolicy
    def initialize(configuration)
      @limits = configuration.limits
    end

    def validate(path, directory: false)
      path = LinuxFilesystem.relative_path(path)
      components = path.split("/")
      depth = components.length - (directory ? 0 : 1)
      if path.bytesize > @limits.fetch(:path_bytes) ||
          components.any? { |part| part.bytesize > @limits.fetch(:component_bytes) } || depth > @limits.fetch(:depth)
        raise LinuxFilesystem::Error.new(:limit_exceeded)
      end
      path
    end

    def candidate(path)
      return :marker if path.split("/").last == ".accio-folder.yml"
      return :markdown if path.downcase.end_with?(".md")
      :unknown
    end
  end
end
