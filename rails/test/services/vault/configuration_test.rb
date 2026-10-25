require_relative "../../support/vault_service_test_helper"

class VaultConfigurationTest < VaultServiceTest
  def test_default_is_unconfigured_and_environment_is_explicit
    refute Vault::Configuration.new.configured?
    refute Vault::Configuration.from_env({}).configured?
    config = Vault::Configuration.from_env("ACCIO_VAULT_PATH" => "relative")
    assert config.configured?
    assert_equal "relative", config.path
  end

  def test_limits_are_finite_and_bounded_by_approved_candidates
    [ { entries: 0 }, { depth: -1 }, { depth: 9 }, { operation_bytes: Float::INFINITY },
      { seconds: Float::NAN }, { seconds: 6 }, { seconds: Complex(1, 1) }, { seconds: "5" },
      { document_bytes: 0 }, { unknown: 1 } ].each do |limits|
      refute Vault::Configuration.new(limits: limits).valid?, limits.inspect
    end
    assert Vault::Configuration.new(limits: { depth: 0, entries: 1, seconds: 0.1 }).valid?
    refute Vault::Configuration.new(path: 42).valid?
    refute Vault::Configuration.new(clock: nil).valid?
    refute Vault::Configuration.new(protected_paths: [ "relative" ]).valid?
  end

  def test_configuration_copies_and_freezes_inputs
    path = "/synthetic/vault"
    protected = "/synthetic/private"
    limits = { entries: 3 }
    config = Vault::Configuration.new(path: path, limits: limits, protected_paths: [ protected ])
    path.replace("changed")
    protected.replace("changed")
    limits[:entries] = 4
    assert_equal "/synthetic/vault", config.path
    assert_equal [ "/synthetic/private" ], config.protected_paths
    assert_equal 3, config.limits.fetch(:entries)
    assert_raises(FrozenError) { config.limits[:entries] = 9 }
  end
end
