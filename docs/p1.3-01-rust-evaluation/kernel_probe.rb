# frozen_string_literal: true

# Synthetic laboratory only. No Vault adapter, Rails, Bundler, or input paths.
# Linux x86_64 constants checked against the installed UAPI headers.
require "fiddle"
require "tmpdir"
require "json"
require "socket"
require "etc"

abort "No arguments accepted" unless ARGV.empty?
abort "Requires unprivileged Ruby 3.3.6 / Linux x86_64" unless
  RUBY_VERSION == "3.3.6" && RUBY_PLATFORM == "x86_64-linux" && !Process.euid.zero?

module KernelProbe
  extend self
  REPO = File.realpath(File.join(__dir__, "../.."))
  O_PATH = 0x200000
  O_DIRECTORY = 0x10000
  O_CLOEXEC = 0x80000
  PIN = O_PATH | File::NOFOLLOW | O_CLOEXEC
  RESOLVE = 0x08 | 0x04 | 0x02 | 0x01 # BENEATH, NO_SYMLINKS, NO_MAGICLINKS, NO_XDEV
  OPENAT = Fiddle::Function.new(Fiddle::Handle::DEFAULT["openat"],
    [Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VARIADIC], Fiddle::TYPE_INT)
  SYSCALL = Fiddle::Function.new(Fiddle::Handle::DEFAULT["syscall"],
    [Fiddle::TYPE_LONG, Fiddle::TYPE_VARIADIC], Fiddle::TYPE_LONG)
  CLOSE = Fiddle::Function.new(Fiddle::Handle::DEFAULT["close"], [Fiddle::TYPE_INT], Fiddle::TYPE_INT)

  def assert(condition)
    raise "synthetic assertion failed" unless condition
  end

  def identity(stat)
    [stat.dev, stat.ino]
  end

  def with_fd(fd)
    errno = Fiddle.last_error # Capture before any other native call.
    raise SystemCallError.new("synthetic open", errno) if fd == -1
    io = nil
    begin
      io = IO.for_fd(fd, autoclose: true)
      yield io
    ensure
      if io
        io.close unless io.closed?
      else
        CLOSE.call(fd) # Ownership was never transferred to Ruby IO.
      end
    end
  end

  def at(root, path, flags = PIN, &block)
    with_fd(OPENAT.call(root.fileno, path, flags), &block)
  end

  def at2(root, path, flags = PIN, resolve = RESOLVE, &block)
    how = [flags, 0, resolve].pack("Q3") # Three native-endian UAPI __u64 fields.
    fd = SYSCALL.call(437, Fiddle::TYPE_LONG, root.fileno,
      Fiddle::TYPE_VOIDP, path, Fiddle::TYPE_VOIDP, how, Fiddle::TYPE_SIZE_T, how.bytesize)
    with_fd(fd, &block)
  end

  def rejects(error)
    begin
      yield
    rescue error => e
      return {errno: e.errno, error: e.class.name}
    end
    raise "expected #{error}"
  end

  # A child performs the mutation after parent descriptors/prechecks exist.
  # A pipe acknowledgement and wait fix the order; no sleeps or timing guesses.
  def mutate
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      begin
        yield
        writer.write("done")
        writer.close
        exit! 0
      rescue Exception
        exit! 1
      end
    end
    writer.close
    acknowledgement = reader.read
    Process.wait(pid)
    assert($?.success? && acknowledgement == "done")
  ensure
    reader&.close unless reader&.closed?
    writer&.close unless writer&.closed?
  end

  def run(name)
    before_fds = Dir.children("/proc/self/fd").sort
    observed = nil
    Dir.mktmpdir(".p1301-kernel-", REPO) do |base|
      initial = identity(File.lstat(base))
      begin
        vault = File.join(base, "vault")
        outside = File.join(base, "outside")
        Dir.mkdir(vault, 0o700)
        Dir.mkdir(outside, 0o700)
        File.binwrite(File.join(vault, "note.md"), "SYNTHETIC-INSIDE\r\n".b)
        File.binwrite(File.join(outside, "note.md"), "SYNTHETIC-OUTSIDE")
        File.open(vault, File::RDONLY | File::NOFOLLOW | O_DIRECTORY | O_CLOEXEC) do |root|
          observed = yield base, vault, outside, root
        end
      ensure
        assert(identity(File.lstat(base)) == initial)
      end
    end
    assert(Dir.children("/proc/self/fd").sort == before_fds)
    {case: name, result: "observed_as_expected", descriptor_set_preserved: true, observed: observed}
  end

  def cases
    results = []
    results << run("openat2_available_with_all_four_resolve_flags") do |_base, vault, _outside, root|
      at2(root, "note.md") do |pin|
        assert(pin.stat.file? && pin.close_on_exec?)
        assert(identity(pin.stat) == identity(File.lstat(File.join(vault, "note.md"))))
        rejects(Errno::EBADF) { pin.sysread(1) }
        {regular: true, close_on_exec: true, content_read: false, open_how_bytes: 24}
      end
    end
    results << run("intermediate_symlink_openat_control_vs_openat2") do |_base, vault, outside, root|
      File.symlink(outside, File.join(vault, "parent"))
      at(root, "parent/note.md") { |pin| assert(identity(pin.stat) == identity(File.stat(File.join(outside, "note.md")))) }
      blocked = rejects(Errno::ELOOP) { at2(root, "parent/note.md") { raise "unexpected success" } }
      File.symlink(".", File.join(vault, "internal"))
      rejects(Errno::ELOOP) { at2(root, "internal/note.md") { raise "unexpected success" } }
      {openat_followed_parent_metadata_only: true, openat2: blocked, internal_symlink_blocked: true}
    end
    results << run("escape_and_absolute_path_rejected_by_kernel") do |_base, _vault, outside, root|
      at(root, "../outside/note.md") { |pin| assert(pin.stat.file?) }
      traversal = rejects(Errno::EXDEV) { at2(root, "../outside/note.md") { raise "unexpected success" } }
      absolute = rejects(Errno::EXDEV) { at2(root, File.join(outside, "note.md")) { raise "unexpected success" } }
      {openat_allows_dotdot: true, openat2_traversal: traversal, openat2_absolute: absolute}
    end
    results << run("final_symlink_is_pinned_not_followed_with_opath_nofollow") do |_base, vault, outside, root|
      File.symlink(File.join(outside, "note.md"), File.join(vault, "link.md"))
      at2(root, "link.md") do |pin|
        assert(pin.stat.symlink?)
        {type: pin.stat.ftype, application_must_reject: true, content_read: false}
      end
    end
    results << run("directory_replacement_after_precheck") do |_base, vault, outside, root|
      parent = File.join(vault, "parent")
      Dir.mkdir(parent)
      File.write(File.join(parent, "note.md"), "SYNTHETIC-ORIGINAL")
      File.lstat(File.join(parent, "note.md"))
      at(root, "parent", PIN | O_DIRECTORY) do |parent_fd|
        mutate do
          File.rename(parent, File.join(vault, "old-parent"))
          File.symlink(outside, parent)
        end
        blocked = rejects(Errno::ELOOP) { at2(root, "parent/note.md") { raise "unexpected success" } }
        at(parent_fd, "note.md") { |pin| assert(identity(pin.stat) == identity(File.stat(File.join(vault, "old-parent/note.md")))) }
        {root_relative_openat2: blocked, old_parent_fd_pins_original: true}
      end
    end
    results << run("moved_directory_dirfd_does_not_prove_original_root_membership") do |_base, vault, outside, root|
      parent = File.join(vault, "parent")
      Dir.mkdir(parent)
      File.write(File.join(parent, "note.md"), "SYNTHETIC-ORIGINAL")
      at2(root, "parent", PIN | O_DIRECTORY) do |parent_fd|
        mutate { File.rename(parent, File.join(outside, "moved")) }
        missing = rejects(Errno::ENOENT) { at2(root, "parent/note.md") { raise "unexpected success" } }
        at2(parent_fd, "note.md") do |pin|
          assert(identity(pin.stat) == identity(File.stat(File.join(outside, "moved/note.md"))))
          {root_relative: missing, moved_parent_relative_openat2_succeeds: true, content_read: false}
        end
      end
    end
    results << run("movement_after_open_remains_possible") do |_base, vault, outside, root|
      at2(root, "note.md") do |pin|
        mutate { File.rename(File.join(vault, "note.md"), File.join(outside, "moved.md")) }
        assert(identity(pin.stat) == identity(File.stat(File.join(outside, "moved.md"))))
        {pin_remains_valid_outside: true, content_read: false, containment_is_at_resolution: true}
      end
    end
    results << run("fifo_socket_directory_pinned_without_content_open") do |_base, vault, _outside, root|
      File.mkfifo(File.join(vault, "fifo"), 0o600)
      Dir.mkdir(File.join(vault, "dir"))
      server = UNIXServer.new(File.join(vault, "socket"))
      types = %w[fifo socket dir].map do |name|
        at2(root, name) { |pin| pin.stat.ftype }
      end
      assert(types == %w[fifo socket directory])
      {types: types, content_read: false, device_nodes_not_tested: true}
    ensure
      server&.close
    end
    results << run("hardlinks_are_allowed_by_openat2_application_must_reject") do |_base, vault, outside, root|
      File.link(File.join(outside, "note.md"), File.join(vault, "hard.md"))
      at2(root, "hard.md") { |pin| assert(pin.stat.nlink == 2) }
      at2(root, "note.md") do |pin|
        assert(pin.stat.nlink == 1)
        mutate { File.link(File.join(vault, "note.md"), File.join(outside, "late.md")) }
        assert(pin.stat.nlink == 2)
      end
      {existing_nlink: 2, late_nlink: 2, content_read: false}
    end
    results << run("regular_pin_reopen_identity_bytes_and_metadata") do |_base, vault, _outside, root|
      path = File.join(vault, "note.md")
      before = File.stat(path)
      at2(root, "note.md") do |pin|
        File.open("/proc/self/fd/#{pin.fileno}", File::RDONLY | File::NONBLOCK | O_CLOEXEC) do |reader|
          assert(identity(reader.stat) == identity(pin.stat) && reader.stat.nlink == 1)
          assert(reader.read(64).b == "SYNTHETIC-INSIDE\r\n".b)
        end
      end
      after = File.stat(path)
      assert([before.size, before.mode, before.mtime, before.ctime, before.dev, before.ino, before.nlink] ==
        [after.size, after.mode, after.mtime, after.ctime, after.dev, after.ino, after.nlink])
      {identity_and_controlled_metadata_preserved: true, atime_not_restored: true, trusted_procfs_required: true}
    end
    results << run("errno_and_exception_cleanup_repeated_without_gc") do |_base, _vault, _outside, root|
      100.times do
        rejects(Errno::ENOENT) { at2(root, "missing.md") { raise "unexpected success" } }
        rejects(Errno::EINVAL) { at2(root, "note.md", PIN, 1 << 63) { raise "unexpected success" } }
        rejects(Errno::ENOENT) { at(root, "missing.md") { raise "unexpected success" } }
        begin
          at2(root, "note.md") { raise ArgumentError, "synthetic caller failure" }
        rescue ArgumentError
          # The descriptor must already be closed by with_fd's ensure.
        end
      end
      {iterations: 100, expected_errors: %w[ENOENT EINVAL], forced_gc: false}
    end
    results
  end
end

results = KernelProbe.cases
abort "Unexpected Rails/database load" if defined?(Rails) || defined?(ActiveRecord) ||
  $LOADED_FEATURES.any? { |path| path.include?("sqlite3") }
puts JSON.pretty_generate(
  purpose: "Kernel / Ruby Fiddle observations; not Rust or Vault validation",
  ruby: RUBY_DESCRIPTION, fiddle: Fiddle::VERSION,
  kernel: Etc.uname.values_at(:sysname, :release).join(" "),
  fixture_location: "fresh private directories inside repository; removed after each case",
  resolve_flags: KernelProbe::RESOLVE, open_how_bytes: 24,
  rust_executed: false, rails_loaded: false, database_loaded: false,
  count: results.length, skips: 0, cases: results
)
