# frozen_string_literal: true

# Laboratory only: this is NOT the Vault adapter or a safe public reader.
# Includes deliberately unsafe negative controls, confined to fresh fixtures.
# Run with plain Ruby, without Rails/Bundler or any inherited Vault setting.
require "tmpdir"
require "json"
require "digest"
require "socket"
require "rbconfig"

abort "No path arguments accepted" unless ARGV.empty?
abort "Probe requires Ruby 3.3.6 on Linux x86_64" unless RUBY_VERSION == "3.3.6" && RUBY_PLATFORM == "x86_64-linux"
abort "Probe requires an unprivileged process" if Process.euid.zero?

module VaultFilesystemProbe
  # From the installed Linux UAPI headers. Deliberately not a portable adapter.
  OPENAT = 257
  O_DIRECTORY = 0x10000
  O_CLOEXEC = 0x80000
  O_PATH = 0x200000
  PIN = O_PATH | File::NOFOLLOW | O_CLOEXEC

  module_function

  def identity(stat)
    [ stat.dev, stat.ino ]
  end

  def openat(parent, name, flags)
    IO.for_fd(Kernel.syscall(OPENAT, parent.fileno, name.dup, flags, 0))
  end

  def with_io(io)
    yield io
  ensure
    io&.close unless io&.closed?
  end

  def assert(value, message = "probe assertion failed")
    raise message unless value
  end

  def raises(error)
    begin
      yield
    rescue error
      return
    end
    raise "expected #{error}"
  end

  # Mutations happen in a child. A pipe acknowledgement fixes their exact order;
  # no probabilistic sleeps. Child failures fail the probe, not skip it.
  def mutation
    done, signal = IO.pipe
    pid = fork do
      done.close
      begin
        yield
        signal.write("done")
        signal.close
        exit! 0
      rescue Exception
        exit! 1
      end
    end
    signal.close
    acknowledgement = done.read
    Process.wait(pid)
    assert($?.success? && acknowledgement == "done", "synthetic writer failed")
  ensure
    done&.close unless done&.closed?
    signal&.close unless signal&.closed?
  end

  def fixture
    Dir.mktmpdir("accio-p1301-probe-", "/tmp") do |base|
      original = identity(File.lstat(base))
      vault = File.join(base, "vault")
      outside = File.join(base, "outside")
      Dir.mkdir(vault, 0o700)
      Dir.mkdir(outside, 0o700)
      File.binwrite(File.join(vault, "note.md"), "\xEF\xBB\xBF---\r\nx: !ruby/object:Opaque {}\r\n---\r\n<script>inert</script>\xFF".b)
      File.binwrite(File.join(outside, "note.md"), "SYNTHETIC-OUTSIDE-SENTINEL")
      File.chmod(0o600, File.join(vault, "note.md"), File.join(outside, "note.md"))
      yield base, vault, outside
    ensure
      assert(identity(File.lstat(base)) == original, "sandbox identity changed; refuse cleanup")
    end
  end

  def with_root(vault)
    with_io(File.open(vault, File::RDONLY | File::NOFOLLOW | O_DIRECTORY)) { |root| yield root }
  end

  def snapshot(path)
    stat = File.lstat(path)
    [ Digest::SHA256.file(path).hexdigest, stat.size, stat.mode, stat.mtime, stat.ctime, stat.ino, stat.dev, stat.nlink ]
  end

  def run(name)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    before_fds = Dir.children("/proc/self/fd").sort
    fixture { |*args| yield(*args) }
    assert(Dir.children("/proc/self/fd").sort == before_fds, "descriptor leak")
    { case: name, result: "observed_as_expected", seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started }
  end

  def cases
    results = []
    results << run("public_api_surface") do
      assert(!File.respond_to?(:openat) && !IO.respond_to?(:openat))
      assert(Dir.respond_to?(:for_fd) && Dir.respond_to?(:fchdir))
      assert(!File::Constants.const_defined?(:PATH, false))
    end
    results << run("final_nofollow_rejects_symlink") do |_base, vault, outside|
      File.symlink(File.join(outside, "note.md"), File.join(vault, "link.md"))
      raises(Errno::ELOOP) { File.open(File.join(vault, "link.md"), File::RDONLY | File::NOFOLLOW) }
    end
    results << run("negative_control_nofollow_does_not_protect_parent") do |_base, vault, outside|
      path = File.join(vault, "parent")
      Dir.mkdir(path)
      File.binwrite(File.join(path, "note.md"), "inside")
      File.realpath(File.join(path, "note.md")) # A successful precheck is insufficient.
      mutation do
        File.rename(path, File.join(vault, "old-parent"))
        File.symlink(outside, path)
      end
      File.open(File.join(path, "note.md"), File::RDONLY | File::NOFOLLOW) do |io|
        assert(io.read == "SYNTHETIC-OUTSIDE-SENTINEL")
      end
    end
    results << run("openat_child_identity_and_cloexec") do |_base, vault|
      with_root(vault) do |root|
        with_io(openat(root, "note.md", PIN)) do |pin|
          assert(pin.stat.file? && pin.close_on_exec?)
          assert(identity(pin.stat) == identity(File.lstat(File.join(vault, "note.md"))))
          raises(Errno::EBADF) { pin.sysread(1) }
        end
      end
    end
    results << run("pin_types_without_reading_fifo_socket_symlink_directory") do |base, vault, outside|
      File.mkfifo(File.join(vault, "fifo"), 0o600)
      File.symlink(outside, File.join(vault, "link"))
      Dir.mkdir(File.join(vault, "dir"))
      server = UNIXServer.new(File.join(vault, "socket"))
      with_root(vault) do |root|
        { "fifo" => "fifo", "socket" => "socket", "link" => "link", "dir" => "directory" }.each do |name, type|
          with_io(openat(root, name, PIN)) { |pin| assert(pin.stat.ftype == type) }
        end
      end
    ensure
      server&.close
    end
    results << run("openat_directory_rejects_symlink_parent") do |_base, vault, outside|
      File.symlink(outside, File.join(vault, "parent"))
      with_root(vault) do |root|
        raises(Errno::ENOTDIR) { openat(root, "parent", PIN | O_DIRECTORY) }
      end
    end
    results << run("anchored_parent_survives_name_replacement") do |_base, vault, outside|
      path = File.join(vault, "parent")
      Dir.mkdir(path)
      File.write(File.join(path, "note.md"), "inside")
      with_root(vault) do |root|
        with_io(openat(root, "parent", PIN | O_DIRECTORY)) do |parent|
          mutation do
            File.rename(path, File.join(vault, "old-parent"))
            File.symlink(outside, path)
          end
          with_io(openat(parent, "note.md", PIN)) do |pin|
            assert(identity(pin.stat) == identity(File.lstat(File.join(vault, "old-parent", "note.md"))))
            assert(identity(pin.stat) != identity(File.lstat(File.join(outside, "note.md"))))
          end
        end
      end
    end
    results << run("root_replacement_detectable_by_identity") do |base, vault|
      with_root(vault) do |root|
        mutation do
          File.rename(vault, File.join(base, "previous-vault"))
          Dir.mkdir(vault, 0o700)
        end
        assert(identity(root.stat) != identity(File.lstat(vault)))
      end
    end
    results << run("limitation_open_directory_can_be_moved_outside_root") do |_base, vault, outside|
      path = File.join(vault, "parent")
      Dir.mkdir(path)
      File.write(File.join(path, "note.md"), "inside")
      with_root(vault) do |root|
        with_io(openat(root, "parent", PIN | O_DIRECTORY)) do |parent|
          mutation { File.rename(path, File.join(outside, "moved")) }
          assert(!File.exist?(path))
          with_io(openat(parent, "note.md", PIN)) do |pin|
            assert(identity(pin.stat) == identity(File.lstat(File.join(outside, "moved", "note.md"))))
          end
        end
      end
    end
    results << run("hardlink_visible_in_fstat_not_realpath") do |_base, vault, outside|
      File.link(File.join(outside, "note.md"), File.join(vault, "hard.md"))
      assert(File.realpath(File.join(vault, "hard.md")) == File.join(vault, "hard.md"))
      with_root(vault) do |root|
        with_io(openat(root, "hard.md", PIN)) { |pin| assert(pin.stat.nlink == 2) }
        assert(root.stat.nlink >= 2) # Directory nlink is not a regular-file policy.
      end
    end
    results << run("late_hardlink_visible_on_pinned_inode") do |_base, vault, outside|
      with_root(vault) do |root|
        with_io(openat(root, "note.md", PIN)) do |pin|
          assert(pin.stat.nlink == 1)
          mutation { File.link(File.join(vault, "note.md"), File.join(outside, "late.md")) }
          assert(pin.stat.nlink == 2)
        end
      end
    end
    results << run("proc_reopen_uses_pinned_regular_inode_after_replace") do |_base, vault, outside|
      original = File.binread(File.join(vault, "note.md"))
      with_root(vault) do |root|
        with_io(openat(root, "note.md", PIN)) do |pin|
          assert(pin.stat.file? && pin.stat.nlink == 1)
          mutation do
            File.rename(File.join(vault, "note.md"), File.join(vault, "old.md"))
            File.symlink(File.join(outside, "note.md"), File.join(vault, "note.md"))
          end
          with_io(File.open("/proc/self/fd/#{pin.fileno}", File::RDONLY | File::NONBLOCK)) do |reader|
            assert(identity(reader.stat) == identity(pin.stat))
            assert(reader.read.b == original && reader.stat.nlink == 1)
          end
        end
      end
    end
    results << run("nofollow_nonblock_fifo_swap_does_not_wait_for_writer") do |_base, vault|
      before = File.lstat(File.join(vault, "note.md"))
      mutation do
        File.unlink(File.join(vault, "note.md"))
        File.mkfifo(File.join(vault, "note.md"), 0o600)
      end
      with_io(File.open(File.join(vault, "note.md"), File::RDONLY | File::NOFOLLOW | File::NONBLOCK)) do |io|
        assert(io.stat.pipe? && identity(io.stat) != identity(before))
      end
    end
    results << run("lstat_fstat_detect_target_replacement") do |_base, vault|
      path = File.join(vault, "note.md")
      before = File.lstat(path)
      mutation do
        File.rename(path, File.join(vault, "previous.md"))
        File.write(path, "new")
      end
      with_io(File.open(path, File::RDONLY | File::NOFOLLOW)) { |io| assert(identity(io.stat) != identity(before)) }
    end
    results << run("in_place_change_observed_between_chunks") do |_base, vault|
      path = File.join(vault, "note.md")
      with_io(File.open(path, File::RDONLY | File::NOFOLLOW)) do |io|
        before = io.stat
        io.read(4)
        mutation { File.write(path, "mutated-and-truncated") }
        after = io.stat
        assert([ before.size, before.mtime, before.ctime ] != [ after.size, after.mtime, after.ctime ])
      end
    end
    results << run("dir_for_fd_enumerates_without_cwd_change") do |_base, vault|
      previous = Dir.pwd
      with_root(vault) do |root|
        fd = root.dup
        fd.autoclose = false # fdopendir takes ownership.
        dir = Dir.for_fd(fd.fileno)
        assert(dir.each_child.to_a == [ "note.md" ])
        dir.close
      end
      assert(Dir.pwd == previous)
    end
    results << run("fchdir_cwd_visible_to_other_threads") do |_base, vault|
      previous = Dir.pwd
      with_root(vault) do |root|
        Dir.fchdir(root.fileno) { assert(Thread.new { Dir.pwd }.value == vault) }
      end
      assert(Dir.pwd == previous)
    end
    results << run("read_preserves_bytes_mode_mtime_ctime_names_identity") do |_base, vault|
      path = File.join(vault, "note.md")
      before = snapshot(path)
      before_atime = File.stat(path).atime
      names = Dir.children(vault)
      with_root(vault) do |root|
        with_io(openat(root, "note.md", PIN)) do |pin|
          with_io(File.open("/proc/self/fd/#{pin.fileno}", File::RDONLY | File::NONBLOCK)) do |reader|
            assert(reader.read.b == File.binread(path))
          end
        end
      end
      assert(snapshot(path) == before && Dir.children(vault) == names)
      assert(File.stat(path).atime >= before_atime) # Accounting, never restored.
    end
    results << run("unreadable_regular_file_cannot_be_reopened_for_content") do |_base, vault|
      path = File.join(vault, "note.md")
      File.chmod(0o000, path)
      with_root(vault) do |root|
        with_io(openat(root, "note.md", PIN)) do |pin|
          assert(pin.stat.file?)
          raises(Errno::EACCES) { File.open("/proc/self/fd/#{pin.fileno}", File::RDONLY | File::NONBLOCK) }
        end
      end
    end
    results << run("fiddle_already_installed_native_bridge_available") do
      require "fiddle"
      assert(Gem.loaded_specs.fetch("fiddle").default_gem?)
      assert($LOADED_FEATURES.any? { |path| path.match?(/fiddle.*\.so\z/) })
      assert(Fiddle::Handle::DEFAULT["openat"].positive?)
    end
    results
  end
end

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
results = VaultFilesystemProbe.cases
abort "Rails or database unexpectedly loaded" if defined?(Rails) || defined?(ActiveRecord) || $LOADED_FEATURES.any? { |p| p.include?("sqlite3") }
puts JSON.pretty_generate(
  purpose: "primitive feasibility only; no Vault service approval",
  ruby: RUBY_DESCRIPTION,
  platform: RUBY_PLATFORM,
  privileged: Process.euid.zero?,
  cases: results,
  count: results.length,
  skips: 0,
  seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
  rails_loaded: !!defined?(Rails),
  database_loaded: !!defined?(ActiveRecord)
)
