begin
  require "fiddle"
rescue LoadError
  # Report an unsupported runtime on use, including when libffi is missing.
end

module Vault
  # Read-only Linux boundary. No caller receives an fd or a path to reopen.
  # Identity checks observe changes; they do not provide a filesystem snapshot.
  class LinuxFilesystem
    class Error < StandardError
      attr_reader :code

      def initialize(code)
        @code = code
        super(code.to_s) # Never include host paths, native messages or content.
      end
    end

    MAX_PATH = 4096
    MAX_COMPONENT = 255
    CHECKOUT = File.expand_path("../../../..", __dir__).freeze

    def self.relative_path(value, allow_root: false)
      raise Error.new(:invalid_path) unless value.is_a?(String)
      path = value.dup.force_encoding(Encoding::UTF_8)
      raise Error.new(:invalid_path) unless path.valid_encoding?
      return path.freeze if allow_root && path.empty?
      parts = path.split("/", -1)
      invalid = !path.valid_encoding? || path.empty? || path.bytesize > MAX_PATH ||
        path.match?(/[\p{Cc}\\:<>"|?*]/) || path.match?(/%(?:25)*(?:2e|2f|5c|00)/i) ||
        parts.any? { |part| part.empty? || [ ".", ".." ].include?(part) || part.bytesize > MAX_COMPONENT ||
          part.match?(/[. ]\z/) || part.match?(/\A(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|\z)/i) }
      raise Error.new(:invalid_path) if invalid
      path.freeze
    end

    def initialize(native: nil, observer: nil)
      @native = native
      @observer = observer || ->(*) { }
    end

    def with_root(value, protected_paths: [])
      path = absolute_root(value, protected_paths)
      native = @native || Native.new
      native.system_root do |system|
        native.pin(system, path.delete_prefix("/"), root: true) do |root|
          stat = native.stat(root)
          raise Error.new(:invalid_root) unless stat.directory? && stat.uid == Process.euid && (stat.mode & 0o077).zero?
          raise Error.new(:unsupported_filesystem) unless Native::LOCAL_FILESYSTEMS.include?(native.filesystem_type(root))
          native.proc_directory(system) do |procfd|
            session = Session.new(native, system, root, procfd, path, stat, @observer)
            session.verify_root!
            result = yield session
            session.verify_root!
            result
          end
        end
      end
    rescue Errno::ENOTDIR
      raise Error.new(:invalid_root)
    rescue SystemCallError => error
      raise Error.new(self.class.error_code(error))
    end

    def self.error_code(error)
      case error
      when Errno::ENOSYS, Errno::EINVAL, Errno::E2BIG then :unsupported_platform
      when Errno::ELOOP, Errno::EXDEV then :blocked_resolution
      when Errno::ENOENT, Errno::ENOTDIR then :not_found
      when Errno::EACCES, Errno::EPERM then :unreadable
      when Errno::EINTR, Errno::EAGAIN then :changed
      when Errno::EMFILE, Errno::ENFILE then :resource_exhausted
      else :io_error
      end
    end

    private

    def absolute_root(value, protected_paths)
      raise Error.new(:invalid_root) unless value.is_a?(String) && value.start_with?("/") && value != "/"
      path = "/#{self.class.relative_path(value.delete_prefix('/'))}"
      # Refuse both containment directions around protected installations/data.
      forbidden = [ CHECKOUT, *protected_paths ].map { |entry| File.expand_path(entry) }
      home = Dir.home
      if forbidden.any? { |entry| related?(entry, path) } || home == path || home.start_with?("#{path}/")
        raise Error.new(:invalid_root)
      end
      path.freeze
    rescue Error
      raise Error.new(:invalid_root)
    end

    def related?(left, right)
      left == right || left.start_with?("#{right}/") || right.start_with?("#{left}/")
    end

    # All ABI details live here. Only the Linux x86_64 LP64 profile is supported.
    class Native
      O_PATH = 0x200000
      O_DIRECTORY = 0x10000
      O_CLOEXEC = 0x80000
      O_NOFOLLOW = 0x20000
      O_NONBLOCK = 0x800
      PIN = O_PATH | O_NOFOLLOW | O_CLOEXEC
      RESOLVE = 0x0f # BENEATH | NO_SYMLINKS | NO_MAGICLINKS | NO_XDEV
      ROOT_RESOLVE = 0x0e # Root configuration may cross a mount; never a link.
      PROC_SUPER_MAGIC = 0x9fa0
      LOCAL_FILESYSTEMS = [ 0xef53, 0x01021994 ].freeze # ext4 family and tmpfs, tested profiles.

      def self.supported?(platform: RUBY_PLATFORM, pointer: nil, long: nil)
        return false unless defined?(Fiddle::Function) && Fiddle.const_defined?(:TYPE_VARIADIC)
        pointer ||= Fiddle::SIZEOF_VOIDP
        long ||= Fiddle::SIZEOF_LONG
        RUBY_ENGINE == "ruby" && platform == "x86_64-linux" && pointer == 8 && long == 8 && [ 1 ].pack("S") == "\x01\x00"
      end

      def initialize
        raise Error.new(:unsupported_platform) unless self.class.supported?
        bind_functions
      end

      def bind_functions
        @syscall = Fiddle::Function.new(Fiddle::Handle::DEFAULT["syscall"],
          [ Fiddle::TYPE_LONG, Fiddle::TYPE_VARIADIC ], Fiddle::TYPE_LONG)
        @statfs = Fiddle::Function.new(Fiddle::Handle::DEFAULT["fstatfs"],
          [ Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP ], Fiddle::TYPE_INT)
        @close = Fiddle::Function.new(Fiddle::Handle::DEFAULT["close"], [ Fiddle::TYPE_INT ], Fiddle::TYPE_INT)
      rescue Fiddle::DLError
        raise Error.new(:unsupported_platform)
      end
      private :bind_functions

      def system_root(&block)
        File.open("/", File::RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW, &block)
      end

      def pin(parent, path, root: false, directory: false, &block)
        flags = PIN | ((root || directory) ? O_DIRECTORY : 0)
        open_descriptor(parent, path, flags, root ? ROOT_RESOLVE : RESOLVE, &block)
      end

      def stat(handle)
        return handle.stat if handle.is_a?(IO)
        # A non-owning view for fstat on a descriptor owned by Dir.
        IO.for_fd(handle.fileno, autoclose: false).stat
      end

      def filesystem_type(handle)
        # struct statfs is 120 bytes in this ABI; only its initial long f_type
        # is read. The zeroed oversized buffer is never exposed to consumers.
        buffer = "\0".b * 256
        result = @statfs.call(handle.fileno, buffer)
        errno = Fiddle.last_error
        raise SystemCallError.new("vault statfs", errno) if result == -1
        buffer.unpack1("l!")
      end

      def proc_directory(system)
        pin(system, "proc", root: true) do |procroot|
          raise Error.new(:procfs_unavailable) unless filesystem_type(procroot) == PROC_SUPER_MAGIC
          pin(procroot, "#{Process.pid}/fd", directory: true) do |procfd|
            raise Error.new(:procfs_unavailable) unless filesystem_type(procfd) == PROC_SUPER_MAGIC
            yield procfd
          end
        end
      rescue SystemCallError
        raise Error.new(:procfs_unavailable)
      end

      def reopen(pin, procfd, directory: false, &block)
        # Intentional magic-link resolution in an already verified procfs fd
        # directory. The numeric name comes only from our live owned pin.
        flags = File::RDONLY | O_NONBLOCK | O_CLOEXEC | (directory ? O_DIRECTORY : 0)
        open_descriptor(procfd, pin.fileno.to_s, flags, 0, directory: directory, &block)
      end

      private

      def open_descriptor(parent, path, flags, resolve, directory: false)
        owner = nil
        Thread.handle_interrupt(Exception => :never) do
          how = [ flags, 0, resolve ].pack("Q3")
          fd = @syscall.call(437, Fiddle::TYPE_LONG, parent.fileno, Fiddle::TYPE_VOIDP, path,
            Fiddle::TYPE_VOIDP, how, Fiddle::TYPE_SIZE_T, how.bytesize)
          errno = Fiddle.last_error
          raise SystemCallError.new("vault openat2", errno) if fd == -1
          begin
            owner = directory ? Dir.for_fd(fd) : IO.for_fd(fd, autoclose: true)
          rescue Exception
            @close.call(fd)
            raise
          end
          begin
            Thread.handle_interrupt(Exception => :immediate) { yield owner }
          ensure
            owner.close
          end
        end
      end
    end

    class Session
      CHUNK = 64 * 1024

      def initialize(native, system, root, procfd, path, stat, observer)
        @native, @system, @root, @procfd = native, system, root, procfd
        @path, @root_stat, @observer = path, stat, observer
      end

      def verify_root!
        @native.pin(@system, @path.delete_prefix("/"), root: true) do |current|
          raise Error.new(:changed) unless root_signature(@native.stat(current)) == root_signature(@root_stat)
        end
      rescue SystemCallError
        raise Error.new(:changed)
      end

      def metadata(path)
        with_pin(path) do |pin, ancestors|
          before = @native.stat(pin)
          verify!(path, pin, ancestors, before)
          before
        end
      end

      def read(path, max_bytes:, remaining_bytes: max_bytes, check: -> { }, on_chunk: ->(_) { })
        unless [ max_bytes, remaining_bytes ].all? { |value| value.is_a?(Integer) && value >= 0 }
          raise ArgumentError, "nonnegative byte limits required"
        end
        with_pin(path) do |pin, ancestors|
          before = @native.stat(pin)
          regular!(before)
          raise Error.new(:limit_exceeded) if before.size > [ max_bytes, remaining_bytes ].min
          @observer.call(:before_reopen, path, 0)
          verify!(path, pin, ancestors, before)
          @native.reopen(pin, @procfd) do |reader|
            regular!(@native.stat(reader))
            raise Error.new(:changed) unless signature(@native.stat(reader)) == signature(before)
            bytes = "".b
            loop do
              @observer.call(:before_read, path, bytes.bytesize)
              check.call
              verify!(path, pin, ancestors, before)
              raise Error.new(:changed) unless signature(@native.stat(reader)) == signature(before)
              break if bytes.bytesize == before.size
              amount = [ CHUNK, before.size - bytes.bytesize, max_bytes - bytes.bytesize, remaining_bytes - bytes.bytesize ].min
              raise Error.new(:limit_exceeded) unless amount.positive?
              chunk = reader.read(amount)
              on_chunk.call(chunk.bytesize) if chunk && !chunk.empty?
              raise Error.new(:changed) unless chunk && chunk.bytesize == amount
              bytes << chunk.b
              @observer.call(:after_chunk, path, chunk.bytesize)
            end
            check.call
            verify!(path, pin, ancestors, before)
            { bytes: bytes.freeze, stat: before, bytes_read: bytes.bytesize }.freeze
          end
        end
      end

      def each_entry(path = "", check: -> { })
        with_pin(path, allow_root: true) do |pin, ancestors|
          before = @native.stat(pin)
          raise Error.new(:special_file) unless before.directory?
          @native.reopen(pin, @procfd, directory: true) do |directory|
            raise Error.new(:changed) unless signature(@native.stat(directory)) == signature(before)
            directory.each_child do |name|
              check.call
              verify!(path, pin, ancestors, before)
              yield name.freeze
            end
            verify!(path, pin, ancestors, before)
          end
        end
      end

      private

      def with_pin(path, allow_root: false)
        path = LinuxFilesystem.relative_path(path, allow_root: allow_root)
        verify_root!
        ancestors = path.split("/")[0...-1].each_with_object({}) do |part, result|
          prefix = result.empty? ? part : "#{result.keys.last}/#{part}"
          @native.pin(@root, prefix) do |pin|
            stat = @native.stat(pin)
            raise Error.new(:blocked_resolution) if stat.symlink?
            raise Error.new(:special_file) unless stat.directory?
            result[prefix] = root_signature(stat)
          end
        end
        @native.pin(@root, path.empty? ? "." : path) do |pin|
          raise Error.new(:changed) unless @native.stat(pin).dev == @root_stat.dev
          @observer.call(:pinned, path, 0)
          yield pin, ancestors
        end
      rescue SystemCallError => error
        raise Error.new(LinuxFilesystem.error_code(error))
      end

      def verify!(path, pin, ancestors, before)
        verify_root!
        ancestors.each do |prefix, expected|
          @native.pin(@root, prefix, directory: true) do |parent|
            raise Error.new(:changed) unless root_signature(@native.stat(parent)) == expected
          end
        end
        raise Error.new(:changed) unless signature(@native.stat(pin)) == signature(before)
        @native.pin(@root, path.empty? ? "." : path) do |current|
          raise Error.new(:changed) unless signature(@native.stat(current)) == signature(before)
        end
      rescue SystemCallError
        raise Error.new(:changed)
      end

      def regular!(stat)
        raise Error.new(:symlink) if stat.symlink?
        raise Error.new(:special_file) unless stat.file?
        raise Error.new(:hardlink) unless stat.nlink == 1
      end

      def root_signature(stat)
        [ stat.dev, stat.ino, stat.mode, stat.uid, stat.gid ]
      end

      def signature(stat)
        [ *root_signature(stat), stat.size, stat.nlink, stat.mtime, stat.ctime ]
      end
    end
  end
end
