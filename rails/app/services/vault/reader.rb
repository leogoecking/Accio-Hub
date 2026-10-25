require "digest"
require_relative "root"
require_relative "path_policy"

module Vault
  class Reader
    def initialize(root)
      @root = root
      @policy = PathPolicy.new(root.configuration)
    end

    def call(path, budget: nil)
      initial = @root.status
      return initial if initial
      path = @policy.validate(path)
      return Result.new(state: :blocked, code: :unsupported_content) if @policy.candidate(path) == :unknown
      budget ||= @root.configuration.budget
      budget.check!
      result = @root.with_session do |session|
        read = session.read(path, max_bytes: @root.configuration.limits.fetch(:document_bytes),
          remaining_bytes: budget.remaining_bytes, check: -> { budget.check! }, on_chunk: ->(count) { budget.consume!(count) })
        Result.new(state: :complete, data: { path: path, bytes: read.fetch(:bytes),
          sha256: Digest::SHA256.hexdigest(read.fetch(:bytes)), metadata: Result.metadata(read.fetch(:stat)) }, metrics: budget.metrics)
      end
      budget.check! if result.success?
      return result if result.metrics.any?
      Result.new(state: result.state, code: result.code, data: result.data, metrics: budget.metrics)
    rescue LinuxFilesystem::Error => error
      Result.failure(error, metrics: budget ? budget.metrics : {})
    end
  end
end
