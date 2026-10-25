# Synthetic measurement only; never accepts a Vault path or loads Rails.
require "json"
require "tmpdir"
require "fileutils"
require "digest"
require "etc"
require_relative "../app/services/vault/reader"
require_relative "../app/services/vault/inventory"

abort "No arguments accepted" unless ARGV.empty?
abort "Unprivileged supported Linux required" if Process.euid.zero? || !Vault::LinuxFilesystem::Native.supported?

module VaultReadonlyMeasure
  extend self
  REPEATS = 5
  SOURCE_SHA256 = [ __FILE__, *Dir[File.expand_path("../app/services/vault/*.rb", __dir__)] ].sort.to_h do |path|
    [ path.delete_prefix(File.expand_path("..", __dir__) + "/"), Digest::SHA256.file(path).hexdigest ]
  end.freeze

  class CountedNative < Vault::LinuxFilesystem::Native
    attr_reader :opened, :closed, :peak

    def initialize
      super
      @opened = @closed = @active = @peak = 0
    end

    [ :system_root, :pin, :reopen ].each do |operation|
      define_method(operation) do |*args, **options, &block|
        entered = false
        begin
          super(*args, **options) do |handle|
            entered = true
            @opened += 1
            @active += 1
            @peak = [ @peak, @active ].max
            block.call(handle)
          end
        ensure
          if entered
            @closed += 1
            @active -= 1
          end
        end
      end
    end
  end

  def assert(value)
    raise "measurement expectation failed" unless value
  end

  def memory
    File.read("/proc/self/status").scan(/^(VmRSS|VmHWM):\s+(\d+) kB$/).to_h.transform_values(&:to_i)
  end

  def snapshot(root)
    [ root, *Dir.glob("#{root}/**/*", File::FNM_DOTMATCH) ].reject { |path| [ ".", ".." ].include?(File.basename(path)) }.sort.to_h do |path|
      stat = File.lstat(path)
      values = [ stat.ftype, stat.mode, stat.size, stat.mtime, stat.ctime, stat.dev, stat.ino, stat.nlink ]
      values << Digest::SHA256.file(path).hexdigest if stat.file?
      [ path.delete_prefix(root), values ]
    end
  end

  def sample(name, parent)
    warn "Measuring #{name} on #{parent}"
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      base = nil
      status = 0
      output = nil
      @natives = []
      begin
        base = Dir.mktmpdir("accio-vault-measure-", parent)
        initial = File.lstat(base)
        vault = File.join(base, "vault")
        Dir.mkdir(vault, 0o700)
        result = yield vault
        assert(!defined?(Rails) && !defined?(ActiveRecord) && !$LOADED_FEATURES.any? { |path| path.include?("sqlite3") })
        assert(@natives.all? { |native| native.opened == native.closed })
        output = JSON.generate(result.merge(name: name, temporary_parent: parent, process_peak_kib: memory.fetch("VmHWM"),
          native_owned_acquisitions: @natives.sum(&:opened), native_owned_releases: @natives.sum(&:closed),
          peak_native_owned_descriptors: @natives.map(&:peak).max || 0))
      rescue Exception => error
        warn "#{name}: #{error.class} #{error.message}"
        status = 1
      ensure
        if base
          current = File.lstat(base)
          if [ current.dev, current.ino ] == [ initial.dev, initial.ino ]
            FileUtils.remove_entry_secure(base)
          else
            warn "Refusing changed synthetic sandbox cleanup"
          end
        end
      end
      writer.write(output) if output
      writer.close
      exit! status
    end
    writer.close
    data = reader.read
    Process.wait(pid)
    assert($?.success?)
    JSON.parse(data)
  ensure
    reader&.close unless reader&.closed?
    writer&.close unless writer&.closed?
  end

  def timings(vault)
    before = snapshot(vault)
    before_fds = Dir.children("/proc/self/fd").sort
    baseline = memory
    observations = []
    seconds = REPEATS.times.map do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      observations << yield
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    end
    assert(snapshot(vault) == before)
    assert(Dir.children("/proc/self/fd").sort == before_fds)
    { repeats: REPEATS, wall_seconds: seconds, p95_seconds: seconds.sort.fetch((REPEATS * 0.95).ceil - 1),
      baseline_rss_kib: baseline.fetch("VmRSS"), controlled_tree_preserved: true, descriptors_preserved: true,
      observations: observations }
  end

  def root(vault, observer: nil, **options)
    native = CountedNative.new
    @natives << native
    filesystem = Vault::LinuxFilesystem.new(native: native, observer: observer)
    Vault::Root.new(Vault::Configuration.new(path: vault, **options), filesystem: filesystem)
  end

  def run(parent)
    cases = []
    file_limit = Vault::Configuration::DEFAULT_LIMITS.fetch(:document_bytes)
    [ file_limit - 1, file_limit, file_limit + 1 ].each do |size|
      cases << sample("document_#{size}", parent) do |vault|
        File.binwrite(File.join(vault, "note.md"), "x" * size)
        reader = Vault::Reader.new(root(vault))
        timings(vault) do
          result = reader.call("note.md")
          assert(result.state == (size <= file_limit ? :complete : :limit_exceeded))
          assert(result.metrics.fetch(:bytes_read) == (size <= file_limit ? size : 0))
          { state: result.state, bytes_read: result.metrics.fetch(:bytes_read) }
        end
      end
    end
    [ 7, 8, 9 ].each do |depth|
      cases << sample("depth_#{depth}", parent) do |vault|
        directory = vault
        depth.times { |n| directory = File.join(directory, "d#{n}"); Dir.mkdir(directory) }
        File.binwrite(File.join(directory, "note.md"), "synthetic")
        inventory = Vault::Inventory.new(root(vault))
        timings(vault) do
          result = inventory.call
          assert(result.state == (depth <= 8 ? :complete : :partial))
          assert(result.metrics.fetch(:bytes_read).zero?)
          { state: result.state, entries: result.metrics.fetch(:entries), bytes_read: 0 }
        end
      end
    end
    [ 9_999, 10_000, 10_001 ].each do |count|
      cases << sample("entries_#{count}", parent) do |vault|
        count.times { |n| File.binwrite(File.join(vault, "entry-#{n}.bin"), "") }
        inventory = Vault::Inventory.new(root(vault))
        timings(vault) do
          result = inventory.call
          assert(result.state == (count <= 10_000 ? :complete : :partial))
          assert(result.metrics.fetch(:entries) == [ count, 10_000 ].min)
          assert(result.code == :entry_limit) if count > 10_000
          { state: result.state, code: result.code, entries: result.metrics.fetch(:entries), bytes_read: result.metrics.fetch(:bytes_read) }
        end
      end
    end
    operation_limit = Vault::Configuration::DEFAULT_LIMITS.fetch(:operation_bytes)
    [ operation_limit - 1, operation_limit, operation_limit + 1 ].each do |requested|
      cases << sample("operation_#{requested}", parent) do |vault|
        File.binwrite(File.join(vault, "full.md"), "x" * file_limit)
        File.binwrite(File.join(vault, "tail.md"), "x" * (file_limit - 1))
        File.binwrite(File.join(vault, "one.md"), "x")
        configured = root(vault)
        reader = Vault::Reader.new(configured)
        timings(vault) do
          budget = configured.configuration.budget
          full_reads = requested < operation_limit ? 15 : 16
          full_reads.times { assert(reader.call("full.md", budget: budget).success?) }
          result = if requested < operation_limit
            reader.call("tail.md", budget: budget)
          elsif requested > operation_limit
            reader.call("one.md", budget: budget)
          else
            Vault::Result.new(state: :complete, metrics: budget.metrics)
          end
          assert(result.state == (requested <= operation_limit ? :complete : :limit_exceeded))
          assert(budget.bytes_read == [ requested, operation_limit ].min)
          { state: result.state, bytes_read: budget.bytes_read, requested_bytes: requested }
        end
      end
    end
    [ 4.999, 5.0, 5.001 ].each do |simulated_seconds|
      cases << sample("deadline_#{simulated_seconds}", parent) do |vault|
        File.binwrite(File.join(vault, "note.md"), "synthetic")
        timings(vault) do
          now = 0.0
          configured = root(vault, clock: -> { now }, observer: ->(event, *) { now = simulated_seconds if event == :before_read })
          result = Vault::Reader.new(configured).call("note.md")
          assert(result.state == (simulated_seconds < 5.0 ? :complete : :limit_exceeded))
          assert(result.metrics.fetch(:bytes_read).zero?) if simulated_seconds >= 5.0
          { state: result.state, simulated_seconds: simulated_seconds, bytes_read: result.metrics.fetch(:bytes_read) }
        end
      end
    end
    cases
  end

  def lexical_boundaries
    [ -1, 0, 1 ].map do |delta|
      path = ([ "a" * 255 ] * 15 + [ "b" * (254 + delta), "c" ]).join("/")
      assert(path.bytesize == 4096 + delta)
      begin
        Vault::LinuxFilesystem.relative_path(path)
        assert(delta <= 0)
        { path_bytes: path.bytesize, accepted_by_outer_lexical_guard: true }
      rescue Vault::LinuxFilesystem::Error => error
        assert(delta > 0 && error.code == :invalid_path)
        { path_bytes: path.bytesize, accepted_by_outer_lexical_guard: false }
      end
    end
  end

  def component_boundaries
    [ 254, 255, 256 ].map do |size|
      begin
        Vault::LinuxFilesystem.relative_path("a" * size)
        assert(size <= 255)
        { component_bytes: size, accepted: true }
      rescue Vault::LinuxFilesystem::Error => error
        assert(size > 255 && error.code == :invalid_path)
        { component_bytes: size, accepted: false }
      end
    end
  end
end

cases = [ "/tmp", "/var/tmp" ].flat_map { |parent| VaultReadonlyMeasure.run(parent) }
puts JSON.pretty_generate(
  purpose: "synthetic read-only measurements; no personal data or Vault release approval",
  ruby: RUBY_DESCRIPTION, kernel: Etc.uname.values_at(:sysname, :release, :machine).join(" "),
  repeats: VaultReadonlyMeasure::REPEATS, cases: cases, lexical_boundaries: VaultReadonlyMeasure.lexical_boundaries,
  component_boundaries: VaultReadonlyMeasure.component_boundaries,
  descriptor_method: "instrumented Native ownership block acquisitions/releases and peak, plus exact /proc/self/fd sets before/after; not syscall tracing",
  source_sha256: VaultReadonlyMeasure::SOURCE_SHA256,
  memory_method: "VmHWM per forked workload; includes runtime, fixture setup, snapshots and repeated operations; not an allocation-only delta",
  p95_method: "nearest rank over five samples; small descriptive sample, not an SLA",
  rails_loaded: false, database_loaded: false
)
