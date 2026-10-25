require_relative "../../support/vault_service_test_helper"

class VaultAuditCorrectionsTest < VaultServiceTest
  FS = Vault::LinuxFilesystem

  def test_ach_vault_01_unreadable_file_reports_file_error_without_payload
    sandbox do |_base, vault|
      path = File.join(vault, "note.md")
      File.chmod(0o000, path)
      before = File.lstat(path)
      root = vault_root(vault)
      assert_equal :ready, root.call.state
      result = Vault::Reader.new(root).call("note.md")
      assert_equal :unreadable, result.state
      assert_equal :unreadable, result.code
      assert_empty result.data
      assert_equal 0, result.metrics.fetch(:bytes_read)
      after = File.lstat(path)
      assert_equal [ before.mode, before.size, before.mtime, before.ctime, before.ino ],
        [ after.mode, after.size, after.mtime, after.ctime, after.ino ]
    end
  end

  def test_ach_vault_01_nested_permission_failure_matches_inventory_entry
    sandbox do |_base, vault|
      directory = File.join(vault, "private")
      Dir.mkdir(directory, 0o700)
      File.write(File.join(directory, "note.md"), "synthetic")
      File.chmod(0o000, directory)
      root = vault_root(vault)
      result = Vault::Reader.new(root).call("private/note.md")
      assert_equal :unreadable, result.state
      assert_equal :unreadable, result.code
      inventory = Vault::Inventory.new(root).call
      assert_equal :partial, inventory.state
      entry = inventory.data.fetch(:entries).find { |item| item[:path] == "private" }
      assert_equal :unreadable, entry.fetch(:state)
      assert_equal :unreadable, entry.fetch(:code)
    ensure
      File.chmod(0o700, directory) if directory
    end
  end

  def test_ach_vault_01_root_acquisition_failure_remains_root_unavailable
    sandbox do |base, vault|
      root = vault_root(vault)
      File.chmod(0o000, base)
      [ root.call, Vault::Reader.new(root).call("note.md"), Vault::Inventory.new(root).call ].each do |result|
        assert_equal :unavailable, result.state
        assert_equal :unreadable, result.code
        assert_empty result.data
      end
    ensure
      File.chmod(0o700, base) if base
    end
  end

  def test_ach_vault_01_consumer_failure_uses_operation_context
    sandbox do |_base, vault|
      result = vault_root(vault).with_session { raise FS::Error.new(:unreadable) }
      assert_equal :unreadable, result.state
      assert_equal :unreadable, result.code
      refute result.success?
    end
  end

  def test_ach_vault_01_root_postcheck_still_runs_after_consumer_failure
    filesystem = Object.new
    checked = false
    filesystem.define_singleton_method(:with_root) do |*, **, &consumer|
      consumer.call(Object.new)
      checked = true
      raise FS::Error.new(:changed)
    end
    root = Vault::Root.new(Vault::Configuration.new(path: "/synthetic/vault"), filesystem: filesystem)
    result = root.with_session { raise FS::Error.new(:unreadable) }
    assert checked, "consumer failure must not bypass the root postcheck"
    assert_equal :changed, result.state
    assert_equal :changed, result.code
    assert_empty result.data
  end

  def test_ach_vault_01_global_inventory_permission_failure_remains_root_scoped
    sandbox do |_base, vault|
      File.chmod(0o000, vault)
      result = Vault::Inventory.new(vault_root(vault)).call
      assert_equal :unavailable, result.state
      assert_equal :unreadable, result.code
      assert_empty result.data
      assert_equal 0, result.metrics.fetch(:bytes_read)
    ensure
      File.chmod(0o700, vault) if vault
    end
  end

  def test_ach_vault_01_programming_errors_are_not_swallowed
    sandbox do |_base, vault|
      error = assert_raises(ArgumentError) { vault_root(vault).with_session { raise ArgumentError, "synthetic consumer bug" } }
      assert_equal "synthetic consumer bug", error.message
    end
  end

  def test_ach_vault_02_from_env_accepts_copied_immutable_protected_paths
    environment = { "ACCIO_VAULT_PATH" => "/synthetic/vault" }
    protected = [ "/synthetic/private" ]
    config = Vault::Configuration.from_env(environment, protected_paths: protected)
    protected.first.replace("changed")
    protected << "/another"
    environment["ACCIO_VAULT_PATH"].replace("changed")
    assert config.valid?
    assert_equal "/synthetic/vault", config.path
    assert_equal [ "/synthetic/private" ], config.protected_paths
    assert config.protected_paths.frozen?
    assert config.protected_paths.first.frozen?
  end

  def test_ach_vault_02_default_and_legacy_environment_calls_remain_compatible
    assert_empty Vault::Configuration.from_env({}).protected_paths
    assert_equal "relative", Vault::Configuration.from_env("ACCIO_VAULT_PATH" => "relative").path
    config = Vault::Configuration.from_env("ACCIO_VAULT_PATH" => "relative", protected_paths: [ "/synthetic/private" ])
    assert_equal "relative", config.path
    assert_equal [ "/synthetic/private" ], config.protected_paths
    ENV.stub(:[], ->(key) { assert_equal "ACCIO_VAULT_PATH", key; "relative" }) do
      assert_equal [ "/synthetic/private" ], Vault::Configuration.from_env(protected_paths: [ "/synthetic/private" ]).protected_paths
    end
  end

  def test_ach_vault_02_does_not_discover_protected_paths_and_keeps_validation
    reads = []
    environment = Object.new
    environment.define_singleton_method(:[]) { |key| reads << key; nil }
    config = Vault::Configuration.from_env(environment, protected_paths: [ "/synthetic/private" ])
    refute config.configured?
    assert_equal [ "ACCIO_VAULT_PATH" ], reads
    refute Vault::Configuration.from_env({}, protected_paths: [ "relative" ]).valid?
    refute Vault::Configuration.from_env({}, protected_paths: [ "/bad\0" ]).valid?
    refute Vault::Configuration.from_env({}, protected_paths: nil).valid?
  end

  def test_ach_vault_02_protected_paths_reach_root_without_native_io
    sandbox do |base, vault|
      native = Object.new
      def native.system_root
        raise "protected root reached native IO"
      end
      [ base, vault, File.join(vault, "private") ].each do |protected|
        config = Vault::Configuration.from_env({ "ACCIO_VAULT_PATH" => vault }, protected_paths: [ protected ])
        result = Vault::Root.new(config, filesystem: adapter(native: native)).call
        assert_equal :invalid_configuration, result.state
        assert_equal :invalid_root, result.code
      end
    end
  end

  def test_ach_vault_03_supported_error_matrix_with_and_without_root_context
    matrix = {
      invalid_root: :invalid_configuration,
      unsupported_platform: :unsupported_platform, unsupported_filesystem: :unsupported_platform,
      changed: :changed, limit_exceeded: :limit_exceeded, timed_out: :limit_exceeded,
      invalid_path: :blocked, blocked_resolution: :blocked, symlink: :blocked, hardlink: :blocked, special_file: :blocked,
      procfs_unavailable: :unavailable, resource_exhausted: :unavailable, io_error: :unavailable,
      not_found: :unavailable
    }
    [ false, true ].each do |root|
      matrix.merge(unreadable: root ? :unavailable : :unreadable).each do |code, expected|
        result = Vault::Result.failure(FS::Error.new(code), root: root, metrics: { bytes_read: 3 })
        assert_equal expected, result.state, "#{code}, root=#{root}"
        assert_equal code, result.code
        assert_equal 3, result.metrics.fetch(:bytes_read)
        assert_empty result.data
        refute result.success?
      end
    end
  end

  def test_ach_vault_03_unknown_errors_are_unavailable_without_false_permission_diagnosis
    [ false, true ].each do |root|
      [ :future_error, nil ].each do |code|
        result = Vault::Result.failure(FS::Error.new(code), root: root)
        assert_equal :unavailable, result.state
        code.nil? ? assert_nil(result.code) : assert_equal(code, result.code)
        assert_empty result.data
        refute result.success?
      end
    end
  end

  def test_ach_vault_03_missing_file_and_root_remain_unavailable
    sandbox do |base, vault|
      result = Vault::Reader.new(vault_root(vault)).call("missing.md")
      assert_equal :unavailable, result.state
      assert_equal :not_found, result.code
      assert_empty result.data
      root = vault_root(File.join(base, "missing"))
      [ root.call, Vault::Reader.new(root).call("note.md"), Vault::Inventory.new(root).call ].each do |failure|
        assert_equal :unavailable, failure.state
        assert_equal :not_found, failure.code
        refute failure.success?
      end
    end
  end

  def test_ach_vault_03_unknown_file_error_makes_inventory_partial
    sandbox do |_base, vault|
      adapter.with_root(vault) do |session|
        filesystem = Object.new
        filesystem.define_singleton_method(:with_root) { |*, **, &consumer| consumer.call(session) }
        root = Vault::Root.new(Vault::Configuration.new(path: vault), filesystem: filesystem)
        session.stub(:metadata, ->(*) { raise FS::Error.new(:future_error) }) do
          result = Vault::Inventory.new(root).call
          assert_equal :partial, result.state
          assert_equal 1, result.metrics.fetch(:entries)
          entry = result.data.fetch(:entries).first
          assert_equal :unavailable, entry.fetch(:state)
          assert_equal :future_error, entry.fetch(:code)
          refute result.success?
        end
      end
    end
  end
end
