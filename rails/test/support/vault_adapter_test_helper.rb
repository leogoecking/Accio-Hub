# Intentionally independent of test_helper: no Rails, ActiveRecord or database.
require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "fileutils"
require "digest"
require "socket"
require_relative "../../app/services/vault/linux_filesystem"

module VaultSyntheticHelpers
  def sandbox
    raise "Synthetic permission tests require an unprivileged user" if Process.euid.zero?
    before_fds = Dir.children("/proc/self/fd").sort
    parent = { "tmp" => "/tmp", "var-tmp" => "/var/tmp" }.fetch(ENV.fetch("ACCIO_VAULT_SYNTHETIC_LOCATION", "tmp"))
    base = Dir.mktmpdir("accio-vault-test-", parent)
    original = File.lstat(base)
    vault, outside = [ "vault", "outside" ].map { |name| File.join(base, name) }
    [ vault, outside ].each { |path| Dir.mkdir(path, 0o700) }
    File.binwrite(File.join(vault, "note.md"), "\xEF\xBB\xBF---\r\nx: !ruby/object:Opaque {}\r\n---\r\n<script>inert</script>\xFF".b)
    File.binwrite(File.join(outside, "note.md"), "SYNTHETIC-OUTSIDE-SENTINEL")
    yield base, vault, outside
  ensure
    if base
      current = File.lstat(base)
      raise "Refuse cleanup: synthetic root identity changed" unless [ current.dev, current.ino ] == [ original.dev, original.ino ]
      FileUtils.remove_entry_secure(base)
      assert_equal before_fds, Dir.children("/proc/self/fd").sort, "residual descriptor without relying on GC"
    end
  end

  def mutate
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      begin
        yield
        writer.write("done")
        writer.close
        exit! 0
      rescue Exception => error
        warn "synthetic mutation failed: #{error.class}: #{error.message}"
        exit! 1
      end
    end
    writer.close
    acknowledgement = reader.read
    Process.wait(pid)
    assert $?.success? && acknowledgement == "done", "synthetic child failed"
  ensure
    reader&.close unless reader&.closed?
    writer&.close unless writer&.closed?
  end

  def error_code(code, &block)
    error = assert_raises(Vault::LinuxFilesystem::Error, &block)
    assert_equal code, error.code
    assert_equal code.to_s, error.message
  end

  def adapter(**options)
    Vault::LinuxFilesystem.new(**options)
  end

  def snapshot(root)
    Dir.glob("#{root}/**/*", File::FNM_DOTMATCH).reject { |path| [ ".", ".." ].include?(File.basename(path)) }.sort.to_h do |path|
      stat = File.lstat(path)
      value = [ stat.ftype, stat.mode, stat.size, stat.mtime, stat.ctime, stat.dev, stat.ino, stat.nlink ]
      value << Digest::SHA256.file(path).hexdigest if stat.file?
      [ path.delete_prefix("#{root}/"), value ]
    end
  end
end

class VaultAdapterTest < Minitest::Test
  include VaultSyntheticHelpers
end
