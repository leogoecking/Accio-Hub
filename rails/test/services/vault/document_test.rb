# Pure synthetic buffers; deliberately does not load Rails/test_helper.
require "minitest/autorun"
require "minitest/mock"
require_relative "../../../app/services/vault/document"
require_relative "../../../app/services/vault/serializer"

class VaultDocumentTest < Minitest::Test
  def note(yaml = "accio_schema: 1\nid: test", body = "body", **options)
    Vault::Document.from_bytes("---\n#{yaml}\n---\n#{body}".b, **options)
  end

  def codes(document)
    document.diagnostics.map { |item| item.fetch(:code) }
  end

  def test_t01_minimal_and_absence
    doc = note
    assert doc.valid_metadata?
    assert_equal :unverified, doc.identity_status
    assert_equal [ "accio_schema", "id" ], doc.metadata.present_fields
    refute doc.metadata.fields.key?("favorite")
    [ "", "   ", "x" * 121 ].each do |title|
      legacy = note("accio_schema: 1\nid: test\ntitle: #{JSON.generate(title)}")
      assert legacy.valid_metadata?
      assert_equal title, legacy.metadata.fields["title"]
      assert_equal legacy.raw_header + "changed".b, Vault::Serializer.new.replace_body(legacy, "changed").bytes
    end
  end

  def test_t12_bytes_and_bom
    raw = "\xEF\xBB\xBF---\r\naccio_schema: 1\nid: ação\n# comment\r\n---\r\nbody\n".b
    doc = Vault::Document.from_bytes(raw)
    assert doc.valid_metadata?
    assert_equal raw, doc.raw_header + doc.raw_body
    assert_equal 3, doc.ranges.fetch(:bom).size
  end
end
