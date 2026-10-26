require_relative "../../support/vault_metadata_test_helper"

class VaultSerializerTest < VaultMetadataTest
  def setup
    @serializer = Vault::Serializer.new
  end

  def test_t22_round_trip_bytes_in_r1_states
    [ "", "\xEF\xBB\xBF".b ].product([ "\n", "\r\n" ], [ "", "body\r\n\ntext\r" ]).each do |bom, eol, body|
      raw = bom.b + "---#{eol}# comentário\naccio_schema: 1#{eol}id: test\nextra: {x: on}#{eol}---#{eol}#{body}".b
      doc = Vault::Document.from_bytes(raw)
      assert doc.valid_metadata?
      [ :unverified, :unique_in_observation ].each do |state|
        source = doc.with_identity(state)
        assert_equal raw, @serializer.original(source).bytes
        replaced = @serializer.replace_body(source, source.raw_body)
        assert replaced.accepted?
        assert_equal raw, replaced.bytes
        assert_equal state, replaced.identity_status
        assert_equal source.source_sha256, replaced.source_sha256
      end
    end
  end

  def test_t23_replacement_guard_and_boundary_without_normalization
    doc = Vault::Document.from_bytes("---\r\naccio_schema: 1\nid: test\r\n---\r\nold".b)
    replacement = "new\nline\r\n".b
    result = @serializer.replace_body(doc, replacement)
    assert_equal doc.raw_header + replacement, result.bytes
    assert_equal doc.raw_header, result.bytes.byteslice(0, doc.raw_header.bytesize)
    replacement.replace("mutated")
    assert result.bytes.end_with?("new\nline\r\n".b)
    assert_raises(FrozenError) { result.bytes << "x" }
    eof = Vault::Document.from_bytes("---\naccio_schema: 1\nid: test\n---".b)
    assert @serializer.replace_body(eof, "").accepted?
    assert_equal [ :ambiguous_body_boundary ], codes(@serializer.replace_body(eof, "body"))
    [ :conflicting, :not_applicable ].each do |state|
      assert_equal [ :unsupported_edit ], codes(@serializer.replace_body(doc.with_identity(state), "body"))
    end
    fake = doc.dup
    fake.instance_variable_set(:@identity_status, :unknown)
    fake.freeze
    refute @serializer.replace_body(fake, "body").accepted?
    [ note("accio_schema: 2\nid: test"), note("accio_schema: 1"), Vault::Document.from_bytes("body".b),
      marker, Vault::Document.from_read_result(Vault::Result.new(state: :unreadable), kind: :note) ].each do |source|
      refute @serializer.replace_body(source, "new").accepted?
    end
    assert_equal [ :invalid_utf8 ], codes(@serializer.replace_body(doc, "\xFF".b))
    assert_equal [ :document_limit ], codes(@serializer.replace_body(doc, "x" * 2_097_153))
    assert_equal [ :wrong_type ], codes(@serializer.replace_body(doc, nil))
    assert_equal [ :document_limit ], codes(@serializer.compose_new(metadata: { "id" => "n", "title" => "new" }, body: "x" * 2_097_153))
    assert_equal [ :wrong_type ], codes(@serializer.compose_new(metadata: { "id" => "n", "title" => "new" }, body: nil))
    assert_equal [ :unsupported_edit ], codes(@serializer.update_properties(doc, title: "new"))
    assert_equal "old".b, doc.raw_body
  end

  def test_t24_new_composition_reparse_defaults_and_no_ids_or_clock
    [ "42", "on", "yes", "a/ç😀", "a\tb", "null", "a\u0085b", "a\u2028b", "a\u2029b" ].each do |id|
      source = { "id" => id, "title" => "Novo", "extra" => { "unknown" => [ "yes", 42, nil ] } }
      body = "body\r\n\n".b
      output = @serializer.compose_new(metadata: source, body: body)
      assert output.accepted?, output.diagnostics.inspect
      assert_nil output.source_sha256
      parsed = Vault::Document.from_bytes(output.bytes)
      assert_equal id, parsed.metadata.fields["id"]
      assert_equal false, parsed.metadata.fields["favorite"]
      assert_equal [], parsed.metadata.fields["tags"]
      assert_equal body, parsed.raw_body
      refute_includes parsed.present_fields, "created_at"
      refute_includes source.keys, "favorite"
      assert_equal output.bytes, @serializer.compose_new(metadata: source, body: body).bytes
    end
    folder = @serializer.compose_new(metadata: { "id" => "folder" }, body: "", kind: :folder)
    assert folder.accepted?
    assert_equal [ "accio_schema", "id" ], Vault::Document.from_bytes(folder.bytes, kind: :folder).present_fields
    refute @serializer.compose_new(metadata: { "title" => "no ID" }, body: "").accepted?
    [ "", " ", "x" * 121, "😀" * 61 ].each do |title|
      refute @serializer.compose_new(metadata: { "id" => "n", "title" => title }, body: "").accepted?
    end
    assert @serializer.compose_new(metadata: { "id" => "n", "title" => "😀" * 60 }, body: "").accepted?
    # Negative control: without escaping NEL the native parser changes the value.
    # Equivalence checking must refuse the draft instead of certifying new bytes.
    unescaped = Class.new(Vault::Serializer) do
      private
      def quoted(value)
        JSON.generate(value)
      end
    end.new
    mismatch = unescaped.compose_new(metadata: { "id" => "a\u0085b", "title" => "x" }, body: "")
    refute mismatch.accepted?
    assert_equal [ :unsupported_edit ], codes(mismatch)
    extra = { "id" => "n", "title" => "a\u0085b", "foreign" => "c\u0085d" }
    preserved = @serializer.compose_new(metadata: extra, body: "")
    assert preserved.accepted?
    doc = Vault::Document.from_bytes(preserved.bytes)
    assert_equal extra["title"], doc.metadata.fields["title"]
    assert_equal extra["foreign"], doc.metadata.extensions["foreign"].value
    bad_encoding = @serializer.compose_new(metadata: { "id" => "n", "title" => "ação".b }, body: "")
    refute bad_encoding.accepted?
    assert_equal [ :wrong_type ], codes(bad_encoding)
    object = Object.new
    def object.to_json(*)
      raise "must never serialize external objects"
    end
    refute @serializer.compose_new(metadata: { "id" => object }, body: "").accepted?
    oversized = { "id" => "n", "title" => "new", "extras" => [ "x" * 8192 ] * 10 }
    rejected = @serializer.compose_new(metadata: oversized, body: "")
    assert_equal [ :header_limit ], codes(rejected)
    escaped = { "id" => "n", "title" => "new", "extra" => [ "\0" * 8192 ] * 2 }
    assert_equal [ :header_limit ], codes(@serializer.compose_new(metadata: escaped, body: ""))
    cyclic = {}
    cyclic["self"] = cyclic
    refute @serializer.compose_new(metadata: cyclic, body: "").accepted?
  end

  def test_t29_does_not_freeze_or_mutate_caller_input
    raw = "---\naccio_schema: 1\nid: test\ntags: [a,a]\nx: {y: z}\n---\nbody".b
    doc = Vault::Document.from_bytes(raw)
    refute raw.frozen?
    raw.replace("different")
    assert doc.valid_metadata?
    assert_raises(FrozenError) { doc.raw_body << "x" }
    assert_raises(FrozenError) { doc.metadata.fields["tags"] << "b" }
    assert_raises(FrozenError) { doc.metadata.extensions["x"]["y"].value << "b" }
    assert_raises(FrozenError) { doc.diagnostics.first[:code] = :other }
    refute_respond_to doc, :save
    refute_respond_to doc, :success?
  end

  def test_t31_hostile_markdown_inert_and_never_yaml_interpreted
    body = "<script>throw 'canary'</script>\n<img src='https://invalid.test'>\n[[new binding]]\n---\n!ruby/object:Object {}\n```yaml\nx: *a\n```\n".b
    doc = note("accio_schema: 1\nid: test", body)
    assert doc.valid_metadata?
    assert_equal body, doc.raw_body
    assert_equal [ "accio_schema", "id" ], doc.present_fields
    assert_equal doc.raw_bytes, @serializer.replace_body(doc, body).bytes
  end
end
