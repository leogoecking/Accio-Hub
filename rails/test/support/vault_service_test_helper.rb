require_relative "vault_adapter_test_helper"
require_relative "../../app/services/vault/configuration"
require_relative "../../app/services/vault/root"
require_relative "../../app/services/vault/path_policy"
require_relative "../../app/services/vault/reader"
require_relative "../../app/services/vault/inventory"
require_relative "../../app/services/vault/result"

class VaultServiceTest < VaultAdapterTest
  def vault_root(path, limits: {}, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, **adapter_options)
    config = Vault::Configuration.new(path: path, limits: limits, clock: clock)
    Vault::Root.new(config, filesystem: adapter(**adapter_options))
  end
end
