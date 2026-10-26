require_relative "../../support/vault_metadata_test_helper"

class VaultMetadataParserTest < VaultMetadataTest
  def test_t02_field_presence_null_types_and_r3
    fields = { "title" => '"hi"', "tags" => '[estudo, estudo, Estudo, " estudo", "é", "é"]',
      "project_ids" => '["p/á"]', "task_ids" => '["u-1"]', "favorite" => "true", "collection" => "journal",
      "link_bindings" => '[{label: " X ", target_id: "n/1", extra: 1}]', "created_at" => "null", "updated_at" => "null" }
    doc = note("accio_schema: 1\nid: test\n" + fields.map { |key, value| "#{key}: #{value}" }.join("\n"))
    assert doc.valid_metadata?
    assert_equal Vault::Metadata::NOTE_FIELDS.sort, doc.present_fields.sort
    assert_equal [ "estudo", "estudo", "Estudo", " estudo", "é", "é" ], doc.metadata.fields["tags"]
    assert_equal 1, codes(doc).count(:duplicate_tag)
    assert_nil doc.metadata.fields["created_at"]
    fields.each_key do |key|
      next if key.end_with?("_at")
      assert_code(:wrong_type, note("accio_schema: 1\nid: test\n#{key}: null"))
    end
    %w[tags project_ids task_ids link_bindings].each do |key|
      assert_code(:wrong_type, note("accio_schema: 1\nid: test\n#{key}: text"))
    end
    %w[project_ids task_ids].each do |key|
      assert_code(:duplicate_value, note("accio_schema: 1\nid: test\n#{key}: [p, p]"))
    end
    assert_code(:unsupported_scalar_form, note("accio_schema: 1\nid: test\nfavorite: TRUE"))
    [ '""', '"   "', '"x\\ny"' ].each do |tag|
      assert_code(:wrong_type, note("accio_schema: 1\nid: test\ntags: [#{tag}]"))
    end
    assert_code(:invalid_enum, note("accio_schema: 1\nid: test\ncollection: other"))
    assert_code(:duplicate_binding, note("accio_schema: 1" + "\nid: test\nlink_bindings: [{label: A, target_id: a}, {label: A, target_id: b}]"))
    assert_code(:missing_field, note("accio_schema: 1\nid: test\nlink_bindings: [{label: a}]"))
    assert_code(:wrong_type, note("accio_schema: 1\nid: test\nlink_bindings: [{label: \"a\\u2028b\", target_id: x}]"))
  end

  def test_t03_unmanaged_and_missing_identity
    [ "body", "\n---\nid: x\n---\n", " ---\nid: x\n---\n" ].each do |raw|
      doc = Vault::Document.from_bytes(raw.b)
      assert_equal :unmanaged, doc.parse_status
      assert_nil doc.claimed_id
    end
    assert_equal :unmanaged, note("id: x").parse_status
    assert_code(:missing_field, note("accio_schema: 1"))
    assert_code(:wrong_type, marker(""))
    assert_code(:missing_field, marker("id: f"))
    assert_code(:missing_field, marker("accio_schema: 1"))
  end

  def test_t04_syntax_framing_and_root_type
    [ "accio_schema: [", "[a,b]", "null", "text" ].each { |yaml| refute note(yaml).valid_metadata? }
    [ "---\nid: x\n...", "---\nid: x\n ---", "---\nid: x\n--- " ].each do |raw|
      assert_code(:unclosed_frontmatter, Vault::Document.from_bytes(raw.b))
    end
    assert_code(:yaml_syntax, note("accio_schema: ["))
    assert_code(:wrong_type, note("[a,b]"))
  end

  def test_t05_duplicate_keys_at_every_depth_and_decoded_keys
    [ "id: other", '"\\u0069d": other', "extra: {a: 1, a: 2}", "extra: [{a: 1, a: 2}]",
      "link_bindings: [{label: A, label: B, target_id: x}]" ].each do |extra|
      doc = note("accio_schema: 1\nid: test\n#{extra}")
      assert_code(:duplicate_key, doc)
      assert_nil doc.claimed_id
    end
    assert note("accio_schema: 1\nid: test\nID: other").valid_metadata?
  end

  def test_t06_explicit_tags_without_core_exceptions
    [ "!ruby/object:Object {}", "!ruby/symbol x", "!ruby/regexp /x/", "!!binary aGVsbG8=", "!!timestamp 2020-01-01",
      "!!str test", "! test", "!local text", "!!map {}", "!!seq []" ].each do |value|
      assert_code(:forbidden_tag, note("accio_schema: 1\nid: test\nextra: #{value}"))
    end
    assert note("accio_schema: 1" + "\nid: test\nextra: \"!local &literal\"").valid_metadata?
    without_tag_guard = Class.new(Vault::Metadata::GuardedTreeBuilder) do
      private
      def node!(anchor, _tag, container: false)
        super(anchor, nil, container: container)
      end
    end
    factory = ->(guard) { without_tag_guard.allocate.tap { |handler| handler.send(:initialize, guard) } }
    Vault::Metadata::GuardedTreeBuilder.stub(:new, factory) do
      control = note("accio_schema: 1\nid: test\nextra: !ruby/object:Object {}")
      assert control.valid_metadata?, "removing the tag policy must be detected by the rejection oracle"
    end
  end

  def test_t07_alias_anchor_and_merge_without_expansion
    [ "&a []", "&a {x: *a}", "&a text" ].each { |value| assert_code(:forbidden_anchor, note("accio_schema: 1\nid: test\nx: #{value}")) }
    assert_code(:forbidden_alias, note("accio_schema: 1\nid: test\nx: *unknown"))
    [ "<<: {}", '"<<": {}', "extra: {<<: {a: b}}" ].each do |value|
      assert_code(:forbidden_merge, note("accio_schema: 1\nid: test\n#{value}"))
    end
    bomb = "accio_schema: 1\nid: test\na: &a [x, x]\nb: &b [*a, *a]\nc: [*b, *b]"
    assert_code(:forbidden_anchor, note(bomb))
  end

  def test_t08_documents_directives_and_body_boundary
    assert_code(:multiple_documents, marker("---\naccio_schema: 1\nid: f\n---\na: b"))
    assert marker("---\naccio_schema: 1\nid: f\n...\n").valid_metadata?
    [ "%YAML 1.2\n---\na: b", "%TAG !e! tag:example.com,2026:\n---\na: b" ].each do |yaml|
      assert_code(:forbidden_directive, marker(yaml))
    end
    assert_code(:wrong_type, marker("# empty\n"))
    doc = note("accio_schema: 1\nid: test\nx: |\n  ---\n  ...", "---\n!ruby/object:Object {}")
    assert doc.valid_metadata?
    assert_equal "---\n!ruby/object:Object {}".b, doc.raw_body
  end

  def test_t09_core_scalar_profile
    %w[yes on OFF NaN +0x2 -0o2].each { |id| assert note("accio_schema: 1\nid: #{id}").valid_metadata?, id }
    %w[true True FALSE null Null NULL ~ 42 +42 -42 00 0o7 0xFF 1.2 1e2 .5 .inf -.Inf .NaN].each do |id|
      assert_code(:wrong_type, note("accio_schema: 1\nid: #{id}"))
    end
    %w[42 true null].each { |id| assert_equal id, note("accio_schema: 1\nid: \"#{id}\"").metadata.fields["id"] }
    assert_code(:wrong_type, note('accio_schema: "1"' + "\nid: test"))
    %w[01 +1 0x1].each { |schema| assert_code(:unsupported_scalar_form, note("accio_schema: #{schema}\nid: test")) }
    [ 0, -1, 2 ].each { |schema| assert_code(:unsupported_schema, note("accio_schema: #{schema}\nid: test"), status: :incompatible) }
    doc = note("accio_schema: 1\nid: test\nx: 9007199254740993\ny: 1.00000000000000001")
    assert_equal :int, doc.metadata.extensions["x"].type
    assert_equal "1.00000000000000001", doc.metadata.extensions["y"].value
  end

  def test_t10_key_policy
    [ "? [a,b]\n: c", "42: x", "true: x", "null: x", '"": x', '"  ": x', '"a\\nb": x' ].each do |extra|
      doc = note("accio_schema: 1\nid: test\n#{extra}")
      refute doc.valid_metadata?, extra
      assert_nil doc.claimed_id
    end
    assert_code(:complex_key, note("accio_schema: 1\nid: test\n? [a,b]\n: c"))
  end

  def test_t11_invalid_encoding_nul_and_multibyte
    [ "---\nid: \xFF\n---\n".b, "---\naccio_schema: 1\nid: x\n---\n\xFF".b, "\xFF\xFE---".b ].each do |raw|
      doc = Vault::Document.from_bytes(raw)
      assert_code(:invalid_utf8, doc, status: :incompatible)
      assert_equal raw, Vault::Serializer.new.original(doc).bytes
    end
    assert_code(:invalid_id, note("accio_schema: 1" + "\nid: \"a\\0b\""))
    assert_code(:unsupported_line_ending, Vault::Document.from_bytes("---\raccio_schema: 1\n".b), status: :incompatible)
    assert_code(:unsupported_line_ending, note("accio_schema: 1\rid: test"), status: :incompatible)
    assert_equal "ação 😀", note("accio_schema: 1\nid: \"a\\u00e7ão 😀\"").metadata.fields["id"]
  end

  def test_t13_opaque_extensions_and_lexical_preservation
    yaml = "# comment\naccio_schema: 1\nid: test\npinned: false\narchived: \"false\"\nextra: {color: azul, nums: [1, 2.50], nested: {x: on}}\ntitle: >\n  a\n  b"
    doc = note(yaml)
    assert doc.valid_metadata?
    assert_equal [ "pinned", "archived", "extra" ], doc.metadata.extensions.keys
    assert_equal :bool, doc.metadata.extensions["pinned"].type
    assert_equal :string, doc.metadata.extensions["archived"].type
    assert_equal "2.50", doc.metadata.extensions["extra"]["nums"][1].value
    assert_equal "a b\n", doc.metadata.fields["title"]
    assert_equal doc.raw_bytes, Vault::Serializer.new.original(doc).bytes
    folder = marker("accio_schema: 1\nid: f\nicon: 2\ncolor: blue\norder: 0\nexpanded: false\ncreated_at: never")
    assert folder.valid_metadata?
    assert_equal [ "accio_schema", "id" ], folder.present_fields
    assert_equal 5, folder.metadata.extensions.size
  end

  def test_t14_dates_strict_with_r2_warning
    valid = %w[0001-01-01T00:00:00Z 9999-12-31T23:59:59.999999999+14:00 2024-02-29T12:01:01-03:00 2026-10-25T00:00:00+00:00]
    valid.each { |date| assert note("accio_schema: 1\nid: test\ncreated_at: #{date}").valid_metadata?, date }
    invalid = %w[0000-01-01T00:00:00Z 1500-02-29T00:00:00Z 2026-02-29T00:00:00Z 2026-01-01 2026-01-01T00:00:00 2026-01-01T24:00:00Z 2026-01-01T00:00:60Z 2026-01-01T00:00:00-00:00 2026-01-01T00:00:00+14:01 2026-01-01T00:00:00+15:00 2026-01-01T00:00:00.1234567890Z]
    invalid.each { |date| assert_code(:invalid_date, note("accio_schema: 1\nid: test\ncreated_at: #{date}")) }
    inverted = note("accio_schema: 1\nid: test\ncreated_at: 2026-01-01T00:00:00.000000002Z\nupdated_at: 2026-01-01T00:00:00.000000001Z")
    assert inverted.valid_metadata?
    assert_includes codes(inverted), :date_order_anomaly
    assert_equal :warning, inverted.diagnostics.find { |d| d[:code] == :date_order_anomaly }[:severity]
    assert_equal "2026-01-01T00:00:00.000000001Z", inverted.metadata.fields["updated_at"]
    same = note("accio_schema: 1\nid: test\ncreated_at: 2026-01-01T00:00:00Z\nupdated_at: 2025-12-31T21:00:00-03:00")
    refute_includes codes(same), :date_order_anomaly
    assert note("accio_schema: 1\nid: test\ncreated_at: null").valid_metadata?
  end

  def test_t15_legacy_ids_literal_without_normalization
    [ "1", " Identificador ", "ação 😀", "42/á?%#项目", "u-abc", "é", "é", "a\tb" ].each do |id|
      doc = note("accio_schema: 1\nid: #{JSON.generate(id)}")
      assert doc.valid_metadata?, id
      assert_equal id, doc.metadata.fields["id"]
    end
    [ "", " ", "\u00a0", "\u3000" ].each { |id| assert_code(:invalid_id, note("accio_schema: 1\nid: #{JSON.generate(id)}")) }
  end

  def test_t27_diagnostics_redacted_and_programming_errors_visible
    doc = note("accio_schema: 1\nid: test\nprivate-secret-name: {x: [}")
    assert_code(:yaml_syntax, doc)
    refute_match(/private-secret|test|\{x/, doc.diagnostics.inspect)
    yaml = "accio_schema: 1\nid: test\n" + (1..40).map { |i| "secret-#{i}: x" }.join("\n")
    doc = note(yaml)
    assert doc.valid_metadata?
    assert_equal 32, doc.diagnostics.size
    assert_equal :diagnostics_truncated, codes(doc).last
    assert_raises(RuntimeError) { Vault::Metadata.stub(:parse, ->(*) { raise "programming canary" }) { note } }
    diagnostics = Vault::Metadata::Diagnostics.new(limits(diagnostics: 2))
    3.times { diagnostics.add(:unknown_field) }
    diagnostics.failure(Vault::Metadata::Rejected.new(:wrong_type))
    assert_includes diagnostics.items.map { |d| d[:severity] }, :error
    single = Vault::Metadata::Diagnostics.new(limits(diagnostics: 1))
    single.failure(Vault::Metadata::Rejected.new(:wrong_type))
    single.add(:unknown_field)
    assert_equal :error, single.items.first[:severity]
  end
end
