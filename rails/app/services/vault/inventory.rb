require_relative "root"
require_relative "path_policy"

module Vault
  class Inventory
    def initialize(root)
      @root = root
      @policy = PathPolicy.new(root.configuration)
    end

    def call
      initial = @root.status
      return initial if initial
      budget = @root.configuration.budget
      entries = []
      result = @root.with_session do |session|
        stop = catch(:vault_inventory_limit) do
          begin
            visit(session, "", entries, budget)
            budget.check!
            nil
          rescue LinuxFilesystem::Error => error
            raise unless error.code == :timed_out
            :timed_out
          end
        end
        entries.sort_by! { |entry| entry.fetch(:path).b }
        counts = entries.each_with_object(Hash.new(0)) { |entry, totals| totals[entry.fetch(:state)] += 1 }
        partial = stop || counts.keys.any? { |state| state != :complete }
        Result.new(state: partial ? :partial : :complete, code: stop,
          data: { entries: entries, counts: counts }, metrics: budget.metrics.merge(entries: entries.length))
      rescue LinuxFilesystem::Error => error
        # Per-entry failures are handled in visit; failure to enumerate the
        # root itself invalidates the global inventory, not an individual file.
        Result.failure(error, root: true)
      end
      # A failed root revalidation invalidates the entire observed collection.
      metrics = budget.metrics.merge(entries: entries.length)
      if result.success? || result.state == :partial
        expired = metrics.fetch(:seconds) >= @root.configuration.limits.fetch(:seconds)
        Result.new(state: expired ? :partial : result.state, code: expired ? :timed_out : result.code,
          data: result.data, metrics: metrics)
      else
        Result.new(state: result.state, code: result.code, metrics: metrics)
      end
    rescue LinuxFilesystem::Error => error
      Result.failure(error, metrics: budget ? budget.metrics : {})
    end

    private

    def visit(session, parent, entries, budget)
      budget.check!
      session.each_entry(parent, check: -> { budget.check! }) do |name|
        throw :vault_inventory_limit, :entry_limit if entries.length >= @root.configuration.limits.fetch(:entries)
        path = parent.empty? ? name : "#{parent}/#{name}"
        entry = { path: path, type: "unknown", size: nil, state: :blocked, code: :invalid_path, candidate: :unknown }
        entries << entry
        begin
          path = @policy.validate(path)
          stat = session.metadata(path)
          budget.check!
          entry.merge!(type: stat.ftype, size: stat.size, candidate: @policy.candidate(path))
          code = blocked_type(stat)
          if code
            entry.merge!(state: :blocked, code: code)
          elsif stat.file? && entry.fetch(:candidate) != :unknown && stat.size > @root.configuration.limits.fetch(:document_bytes)
            entry.merge!(state: :limit_exceeded, code: :document_limit)
          else
            @policy.validate(path, directory: true) if stat.directory?
            entry.merge!(state: :complete, code: nil)
            visit(session, path, entries, budget) if stat.directory?
          end
        rescue LinuxFilesystem::Error => error
          failure = Result.failure(error)
          entry.merge!(state: failure.state, code: failure.code)
          raise if error.code == :timed_out
        end
      end
    rescue LinuxFilesystem::Error => error
      raise if parent.empty? || error.code == :timed_out
      entry = entries.find { |item| item.fetch(:path) == parent }
      entry&.merge!(state: Result.failure(error).state, code: error.code)
    end

    def blocked_type(stat)
      return :symlink if stat.symlink?
      return :special_file unless stat.file? || stat.directory?
      :hardlink if stat.file? && stat.nlink != 1
    end
  end
end
