require_relative "../../support/vault_service_test_helper"

class VaultRootTest < VaultServiceTest
  def test_unconfigured_and_invalid_configuration_do_no_candidate_io
    deny = Object.new
    def deny.with_root(*)
      raise "unexpected candidate IO"
    end
    [ nil, "" ].each do |path|
      root = Vault::Root.new(Vault::Configuration.new(path: path), filesystem: deny)
      assert_equal :unconfigured, root.call.state
      assert_equal :unconfigured, Vault::Reader.new(root).call("../invalid").state
      assert_equal :unconfigured, Vault::Inventory.new(root).call.state
    end
    config = Vault::Configuration.new(path: "/synthetic", limits: { entries: -1 })
    assert_equal :invalid_configuration, Vault::Root.new(config, filesystem: deny).call.state
  end

  def test_root_is_checked_on_each_operation_and_never_created
    sandbox do |base, vault|
      root = vault_root(vault)
      assert_equal :ready, root.call.state
      File.rename(vault, File.join(base, "old"))
      result = root.call
      assert_equal :unavailable, result.state
      assert_equal :not_found, result.code
      refute File.exist?(vault)
    end
  end

  def test_changed_root_invalidates_reader_output
    sandbox do |base, vault|
      once = false
      root = vault_root(vault, observer: lambda { |event, *|
        if event == :before_read && !once
          once = true
          mutate { File.rename(vault, File.join(base, "moved")) }
        end
      })
      result = Vault::Reader.new(root).call("note.md")
      assert_equal :changed, result.state
      assert_empty result.data
      assert_equal 0, result.metrics.fetch(:bytes_read)
    end
  end
end
