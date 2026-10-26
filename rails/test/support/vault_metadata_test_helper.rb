require "minitest/autorun"
require "minitest/mock"
require_relative "../../app/services/vault/document"
require_relative "../../app/services/vault/serializer"
require_relative "../../app/services/vault/metadata/identity_set"

class VaultMetadataTest < Minitest::Test
  def note(yaml = "accio_schema: 1\nid: test", body = "body", **options)
    Vault::Document.from_bytes("---\n#{yaml}\n---\n#{body}".b, **options)
  end

  def marker(yaml = "accio_schema: 1\nid: folder", **options)
    Vault::Document.from_bytes(yaml.b, kind: :folder, **options)
  end

  def codes(value)
    value.diagnostics.map { |item| item.fetch(:code) }
  end

  def assert_code(code, document, status: :invalid)
    assert_equal status, document.parse_status
    assert_includes codes(document), code
    refute document.valid_metadata?
    assert_nil document.metadata
  end

  def limits(**values)
    Vault::Metadata::Limits.new(**values)
  end

  def description(doc = note, path: "a.md")
    Vault::Metadata::IdentitySet.describe(doc).merge(path: path)
  end

  def observe(entries, complete: true, **options)
    Vault::Metadata::IdentitySet.call(entries, scope: "synthetic", complete: complete, **options)
  end
end
