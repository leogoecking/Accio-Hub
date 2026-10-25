require_relative "../../support/vault_service_test_helper"

class VaultPathPolicyTest < VaultServiceTest
  def test_portable_names_preserve_unicode_and_case_without_normalization
    policy = Vault::PathPolicy.new(Vault::Configuration.new)
    [ "Notas/ação.md", "Notas/ac\u0327a\u0303o.md", ".hidden/Note.MD", "x%41.md" ].each do |path|
      assert_equal path.b, policy.validate(path).b
    end
    assert_equal :markdown, policy.candidate("Note.MD")
    assert_equal :marker, policy.candidate("a/.accio-folder.yml")
    assert_equal :unknown, policy.candidate("opaque.yml")
  end

  def test_byte_and_depth_boundaries
    config = Vault::Configuration.new(limits: { path_bytes: 12, component_bytes: 8, depth: 1 })
    policy = Vault::PathPolicy.new(config)
    [ "aaaaaaa", "aaaaaaaa" ].each { |path| assert_equal path, policy.validate(path) }
    error_code(:limit_exceeded) { policy.validate("aaaaaaaaa") }
    assert_equal "abc/1234567", policy.validate("abc/1234567")
    assert_equal "abc/12345678", policy.validate("abc/12345678")
    error_code(:limit_exceeded) { policy.validate("abcd/12345678") }
    assert_equal "a/b.md", policy.validate("a/b.md")
    error_code(:limit_exceeded) { policy.validate("a/b/c.md") }
    error_code(:limit_exceeded) { policy.validate("a/b", directory: true) }
  end

  def test_invalid_paths_are_refused_before_even_opening_the_root
    deny = Object.new
    def deny.with_root(*)
      raise "invalid note path reached root IO"
    end
    root = Vault::Root.new(Vault::Configuration.new(path: "/synthetic/vault"), filesystem: deny)
    [ "../x.md", "/x.md", "%252e%252e/x.md", "a//x.md", "x\0.md", "x:ads.md", "x\\y.md", "NUL.md" ].each do |path|
      result = Vault::Reader.new(root).call(path)
      assert_equal :blocked, result.state
      assert_equal :invalid_path, result.code
    end
  end
end
