require_relative "../../support/vault_adapter_test_helper"

class VaultLinuxFilesystemTest < VaultAdapterTest
  FS = Vault::LinuxFilesystem

  def test_regular_bytes_and_static_tree_are_preserved
    sandbox do |_base, vault|
      File.binwrite(File.join(vault, "unknown.bin"), "opaque")
      before = snapshot(vault)
      expected = File.binread(File.join(vault, "note.md"))
      adapter.with_root(vault) do |root|
        result = root.read("note.md", max_bytes: 1024)
        assert_equal expected, result.fetch(:bytes)
        assert result.fetch(:bytes).frozen?
        assert_equal expected.bytesize, result.fetch(:bytes_read)
        names = []
        root.each_entry { |name| names << name }
        assert_equal [ "note.md", "unknown.bin" ], names.sort
      end
      assert_equal before, snapshot(vault)
    end
  end

  def test_unsupported_platform_and_abi_are_refused_before_native_calls
    refute FS::Native.supported?(platform: "x64-mingw-ucrt")
    refute FS::Native.supported?(platform: "aarch64-linux")
    refute FS::Native.supported?(pointer: 4)
    refute FS::Native.supported?(long: 4)
    FS::Native.stub(:supported?, false) { error_code(:unsupported_platform) { FS::Native.new } }
  end

  def test_loading_does_not_require_platform_specific_ruby_constants
    source = File.expand_path("../../../app/services/vault/linux_filesystem.rb", __dir__)
    mutate do
      File::Constants.send(:remove_const, :NOFOLLOW)
      Object.send(:remove_const, :Vault)
      load source
      raise "profile failed" unless Vault::LinuxFilesystem::Native.supported?
    end
  end

  def test_missing_fiddle_reports_unsupported_instead_of_failing_file_load
    source = File.expand_path("../../../app/services/vault/linux_filesystem.rb", __dir__)
    mutate do
      Object.send(:remove_const, :Vault)
      Object.send(:remove_const, :Fiddle)
      Kernel.prepend(Module.new do
        def require(path)
          raise LoadError, "synthetic missing Fiddle" if path == "fiddle"
          super
        end
      end)
      load source
      raise "unsupported profile accepted" if Vault::LinuxFilesystem::Native.supported?
      begin
        Vault::LinuxFilesystem::Native.new
        raise "missing Fiddle accepted"
      rescue Vault::LinuxFilesystem::Error => error
        raise "wrong error" unless error.code == :unsupported_platform
      end
    end
  end

  def test_invalid_roots_and_protected_locations_are_refused_before_native_io
    native = Object.new
    def native.system_root
      raise "unexpected native IO"
    end
    [ nil, "", "relative", "/", "/tmp/../bad", "/tmp//bad", "/tmp/bad\0", FS::CHECKOUT, Dir.home ].each do |path|
      error_code(:invalid_root) { adapter(native: native).with_root(path) { flunk } }
    end
    sandbox do |base, vault|
      [ base, vault, File.join(vault, "private") ].each do |protected|
        error_code(:invalid_root) { adapter(native: native).with_root(vault, protected_paths: [ protected ]) { flunk } }
      end
    end
  end

  def test_root_must_be_owned_private_directory_with_no_symbolic_components
    sandbox do |base, vault|
      File.chmod(0o755, vault)
      error_code(:invalid_root) { adapter.with_root(vault) { flunk } }
      File.chmod(0o700, vault)
      error_code(:invalid_root) { adapter.with_root(File.join(vault, "note.md")) { flunk } }
      File.symlink(vault, File.join(base, "alias"))
      error_code(:blocked_resolution) { adapter.with_root(File.join(base, "alias", "nested")) { flunk } }
      assert_raises(FS::Error) { adapter.with_root(File.join(base, "alias")) { flunk } }
    end
  end

  def test_missing_root_and_permission_denied_are_explicit
    sandbox do |base, vault|
      error_code(:not_found) { adapter.with_root(File.join(base, "missing")) { flunk } }
      File.chmod(0o000, vault)
      error_code(:unreadable) { adapter.with_root(vault) { |root| root.read("note.md", max_bytes: 1024) } }
    end
  end

  def test_invalid_paths_never_reach_native_pin
    sandbox do |_base, vault|
      native = FS::Native.new
      adapter(native: native).with_root(vault) do |root|
        native.stub(:pin, ->(*) { flunk "invalid path reached native IO" }) do
        [ "", "/note.md", "../outside/note.md", "x/../../outside", "x//y", "x/./y", "x/", "x\\y", "C:/x", "//host/share", "x:ads", "a\0", "a\n", "%2e%2e/x", "%252e%252e/x", "x%2fy", "x%255cy", "CON.md", "LPT1", "a.", "a ", "x" * 256, "\xff".b ].each do |path|
          error_code(:invalid_path) { root.read(path, max_bytes: 1024) }
        end
        end
      end
    end
  end

  def test_all_final_and_intermediate_symlinks_are_blocked_for_content
    sandbox do |_base, vault, outside|
      File.symlink("note.md", File.join(vault, "internal.md"))
      File.symlink(File.join(outside, "note.md"), File.join(vault, "external.md"))
      File.symlink("missing", File.join(vault, "broken.md"))
      File.symlink("loop.md", File.join(vault, "loop.md"))
      File.symlink(outside, File.join(vault, "parent"))
      File.symlink(".", File.join(vault, "internal"))
      adapter.with_root(vault) do |root|
        %w[internal.md external.md broken.md loop.md].each do |path|
          assert root.metadata(path).symlink?
          error_code(:symlink) { root.read(path, max_bytes: 1024) }
        end
        %w[parent/note.md internal/note.md].each do |path|
          error_code(:blocked_resolution) { root.read(path, max_bytes: 1024) }
        end
      end
    end
  end

  def test_existing_hardlinks_are_blocked_before_content_read
    sandbox do |_base, vault, outside|
      File.link(File.join(outside, "note.md"), File.join(vault, "hard.md"))
      reads = []
      adapter(observer: ->(event, *) { reads << event if event == :after_chunk }).with_root(vault) do |root|
        assert_equal 2, root.metadata("hard.md").nlink
        error_code(:hardlink) { root.read("hard.md", max_bytes: 1024) }
      end
      assert_empty reads
    end
  end

  def test_specials_are_identified_without_opening_content
    sandbox do |_base, vault|
      File.mkfifo(File.join(vault, "fifo.md"), 0o600)
      Dir.mkdir(File.join(vault, "directory.md"))
      server = UNIXServer.new(File.join(vault, "socket.md"))
      chunks = 0
      adapter(observer: ->(event, *) { chunks += 1 if event == :after_chunk }).with_root(vault) do |root|
        %w[fifo.md socket.md directory.md].each { |path| error_code(:special_file) { root.read(path, max_bytes: 1024) } }
        assert root.metadata("fifo.md").pipe?
        assert root.metadata("socket.md").socket?
      end
      assert_equal 0, chunks
    ensure
      server&.close
    end
  end

  def test_file_replaced_with_fifo_after_pin_is_changed_without_content_read
    race(:pinned) do |_base, vault, _outside|
      File.rename(File.join(vault, "note.md"), File.join(vault, "old.md"))
      File.mkfifo(File.join(vault, "note.md"), 0o600)
    end
  end

  def test_parent_replaced_by_external_symlink_after_pin_is_changed
    race(:pinned, nested: true) do |_base, vault, outside|
      File.rename(File.join(vault, "parent"), File.join(vault, "old-parent"))
      File.symlink(outside, File.join(vault, "parent"))
    end
  end

  def test_parent_moved_outside_after_pin_is_changed_before_read
    race(:before_read, nested: true) do |_base, vault, outside|
      File.rename(File.join(vault, "parent"), File.join(outside, "moved"))
    end
  end

  def test_root_replaced_after_pin_is_changed_before_read
    race(:before_read) do |base, vault|
      File.rename(vault, File.join(base, "old-vault"))
      Dir.mkdir(vault, 0o700)
    end
  end

  def test_target_moved_outside_after_reopen_is_changed_before_read
    race(:before_read) do |_base, vault, outside|
      File.rename(File.join(vault, "note.md"), File.join(outside, "moved.md"))
    end
  end

  def test_hardlink_added_before_reopen_is_refused_before_read
    race(:before_reopen) do |_base, vault, outside|
      File.link(File.join(vault, "note.md"), File.join(outside, "hard.md"))
    end
  end

  def test_in_place_mutation_between_chunks_discards_result
    sandbox do |_base, vault|
      File.binwrite(File.join(vault, "note.md"), "a" * (FS::Session::CHUNK + 32))
      once = false
      reader = adapter(observer: lambda { |event, *|
        if event == :after_chunk && !once
          once = true
          mutate { File.binwrite(File.join(vault, "note.md"), "changed") }
        end
      })
      error_code(:changed) { reader.with_root(vault) { |root| root.read("note.md", max_bytes: 100_000) } }
      assert once
    end
  end

  def test_limits_are_checked_before_reading_and_exact_limit_is_accepted
    sandbox do |_base, vault|
      File.binwrite(File.join(vault, "note.md"), "abcd")
      adapter.with_root(vault) do |root|
        error_code(:limit_exceeded) { root.read("note.md", max_bytes: 3) }
        error_code(:limit_exceeded) { root.read("note.md", max_bytes: 4, remaining_bytes: 3) }
        assert_equal "abcd", root.read("note.md", max_bytes: 4).fetch(:bytes)
        File.binwrite(File.join(vault, "empty.md"), "")
        assert_equal "", root.read("empty.md", max_bytes: 0).fetch(:bytes)
      end
    end
  end

  def test_procfs_missing_or_wrong_filesystem_is_refused
    sandbox do |_base, vault|
      native = FS::Native.new
      original_pin = native.method(:pin)
      native.stub(:pin, lambda { |parent, path, **options, &block|
        raise Errno::ENOENT if path == "proc"
        original_pin.call(parent, path, **options, &block)
      }) { error_code(:procfs_unavailable) { adapter(native: native).with_root(vault) { flunk } } }
      original_type = native.method(:filesystem_type)
      native.stub(:filesystem_type, ->(io) { type = original_type.call(io); type == FS::Native::PROC_SUPER_MAGIC ? 0 : type }) do
        error_code(:procfs_unavailable) { adapter(native: native).with_root(vault) { flunk } }
      end
    end
  end

  def test_reopen_identity_mismatch_never_reads_the_substituted_file
    sandbox do |_base, vault, outside|
      native = FS::Native.new
      native.stub(:reopen, lambda { |*, **, &block| File.open(File.join(outside, "note.md"), "rb", &block) }) do
        error_code(:changed) { adapter(native: native).with_root(vault) { |root| root.read("note.md", max_bytes: 1024) } }
      end
    end
  end

  def test_no_openat_fallback_and_native_errors_are_redacted
    sandbox do |_base, vault|
      { Errno::ENOSYS => :unsupported_platform, Errno::EINVAL => :unsupported_platform,
        Errno::E2BIG => :unsupported_platform, Errno::EAGAIN => :changed,
        Errno::EINTR => :changed, Errno::EIO => :io_error,
        Errno::EMFILE => :resource_exhausted, Errno::EPERM => :unreadable }.each do |error, code|
        native = FS::Native.new
        native.stub(:pin, ->(*) { raise error, "PRIVATE-HOST-PATH" }) do
          error_code(code) { adapter(native: native).with_root(vault) { flunk } }
        end
      end
    end
  end

  def test_resources_close_under_caller_and_enumeration_exceptions_without_gc
    sandbox do |_base, vault|
      25.times do
        assert_raises(RuntimeError) { adapter.with_root(vault) { raise "caller" } }
        assert_raises(RuntimeError) { adapter.with_root(vault) { |root| root.each_entry { raise "iterator" } } }
        assert_raises(RuntimeError) do
          adapter(observer: ->(event, *) { raise "reader" if event == :before_read }).with_root(vault) do |root|
            root.read("note.md", max_bytes: 1024)
          end
        end
      end
    end
  end

  def test_descriptor_is_cloexec_and_raw_fd_adoption_failure_closes_it
    sandbox do |_base, vault|
      adapter.with_root(vault) { |_root| assert Dir.children("/proc/self/fd").any? }
      native = FS::Native.new
      native.system_root do |system|
        native.pin(system, vault.delete_prefix("/"), root: true) { |pin| assert pin.close_on_exec? }
        IO.stub(:for_fd, ->(*) { raise ArgumentError, "adoption failure" }) do
          assert_raises(ArgumentError) { native.pin(system, vault.delete_prefix("/"), root: true) { flunk } }
        end
      end
    end
  end

  def test_unknown_filesystem_is_refused
    sandbox do |_base, vault|
      native = FS::Native.new
      native.stub(:filesystem_type, 0x6969) do
        error_code(:unsupported_filesystem) { adapter(native: native).with_root(vault) { flunk } }
      end
    end
  end

  def test_device_type_is_simulated_at_adapter_boundary_and_never_reopened
    sandbox do |_base, vault|
      native = FS::Native.new
      target = File.stat(File.join(vault, "note.md")).ino
      original_stat = native.method(:stat)
      native.stub(:stat, lambda { |io|
        stat = original_stat.call(io)
        stat.define_singleton_method(:file?) { false } if stat.ino == target
        stat
      }) do
        native.stub(:reopen, ->(*) { flunk "special file reached content reopen" }) do
          error_code(:special_file) { adapter(native: native).with_root(vault) { |root| root.read("note.md", max_bytes: 1024) } }
        end
      end
    end
  end

  def test_directory_fd_adoption_failure_closes_raw_fd
    sandbox do |_base, vault|
      Dir.stub(:for_fd, ->(*) { raise ArgumentError, "directory adoption failure" }) do
        assert_raises(ArgumentError) { adapter.with_root(vault) { |root| root.each_entry { flunk } } }
      end
    end
  end

  def test_thread_interruption_closes_descriptors
    sandbox do |_base, vault|
      entered, hold = Queue.new, Queue.new
      thread = Thread.new do
        adapter(observer: lambda { |event, *|
          if event == :before_read
            entered << true
            hold.pop
          end
        }).with_root(vault) { |root| root.read("note.md", max_bytes: 1024) }
      end
      entered.pop
      thread.kill
      thread.join
      refute thread.alive?
    ensure
      thread&.kill
      thread&.join
    end
  end

  def test_unreadable_content_and_cooperative_deadline_close_resources
    sandbox do |_base, vault|
      File.chmod(0o000, File.join(vault, "note.md"))
      error_code(:unreadable) { adapter.with_root(vault) { |root| root.read("note.md", max_bytes: 1024) } }
      File.chmod(0o600, File.join(vault, "note.md"))
      error_code(:timed_out) do
        adapter.with_root(vault) { |root| root.read("note.md", max_bytes: 1024, check: -> { raise FS::Error.new(:timed_out) }) }
      end
    end
  end

  def test_root_owner_and_permission_changes_are_refused
    sandbox do |_base, vault|
      native = FS::Native.new
      root_inode = File.stat(vault).ino
      original_stat = native.method(:stat)
      native.stub(:stat, lambda { |io|
        stat = original_stat.call(io)
        stat.define_singleton_method(:uid) { Process.euid + 1 } if stat.ino == root_inode
        stat
      }) { error_code(:invalid_root) { adapter(native: native).with_root(vault) { flunk } } }
      race_reader = adapter(observer: ->(event, *) { File.chmod(0o755, vault) if event == :before_read })
      error_code(:changed) { race_reader.with_root(vault) { |root| root.read("note.md", max_bytes: 1024) } }
    end
  end

  private

  def race(event, nested: false)
    sandbox do |base, vault, outside|
      path = "note.md"
      if nested
        Dir.mkdir(File.join(vault, "parent"))
        File.rename(File.join(vault, path), File.join(vault, "parent", path))
        path = "parent/note.md"
      end
      once = false
      chunks = 0
      reader = adapter(observer: lambda { |seen, *|
        chunks += 1 if seen == :after_chunk
        if seen == event && !once
          once = true
          mutate { yield base, vault, outside }
        end
      })
      error_code(:changed) { reader.with_root(vault) { |root| root.read(path, max_bytes: 1024) } }
      assert once
      assert_equal 0, chunks, "no body read after observable replacement"
    end
  end
end
