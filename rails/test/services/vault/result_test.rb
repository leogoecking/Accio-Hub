require_relative "../../support/vault_service_test_helper"

class VaultResultTest < VaultServiceTest
  def test_result_is_deeply_immutable_without_freezing_caller_values
    source = { entries: [ { path: "x.md" } ] }
    result = Vault::Result.new(state: :complete, data: source)
    source[:entries][0][:path].replace("y.md")
    assert_equal "x.md", result.data.fetch(:entries).first.fetch(:path)
    assert result.success?
    assert_raises(FrozenError) { result.data.fetch(:entries) << {} }
    assert_raises(FrozenError) { result.data.fetch(:entries).first.fetch(:path).replace("z") }
  end
end
