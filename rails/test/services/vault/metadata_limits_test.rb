require "open3"
require_relative "../../support/vault_metadata_test_helper"

class VaultMetadataLimitsTest < VaultMetadataTest
  def test_t25_only_reductions_and_prechecks
    assert_equal 16, limits[:depth]
    assert_equal 4096, limits[:nodes]
    Vault::Metadata::Limits::DEFAULTS.each do |key, value|
      assert_raises(ArgumentError) { limits(**{ key => value + 1 }) }
      assert_raises(ArgumentError) { limits(**{ key => 0 }) }
    end
    assert_raises(ArgumentError) { limits(unknown: 1) }
    assert_raises(ArgumentError) { limits(seconds: Float::NAN) }
    assert_raises(FrozenError) { limits.instance_variable_get(:@values)[:depth] = 10 }
    parser_called = false
    Vault::Metadata.stub(:parse, ->(*) { parser_called = true; raise "must not parse" }) do
      assert_code(:header_limit, note("accio_schema: 1\nid: test", parser_limits: limits(header_bytes: 10)), status: :limit_exceeded)
    end
    refute parser_called
    [ 65_535, 65_536, 65_537 ].each do |size|
      base = "---\naccio_schema: 1\nid: test\n#"
      raw = (base + "x" * (size - base.bytesize - 5) + "\n---\n").b
      assert_equal size, raw.bytesize
      doc = Vault::Document.from_bytes(raw)
      size <= 65_536 ? assert(doc.valid_metadata?) : assert_code(:header_limit, doc, status: :limit_exceeded)
    end
    [ 2047, 2048, 2049 ].each do |lines|
      yaml = "accio_schema: 1\nid: test\n" + "#\n" * (lines - 2)
      doc = Vault::Document.from_bytes("---\n#{yaml}---\n".b)
      lines <= 2048 ? assert(doc.valid_metadata?) : assert_code(:line_limit, doc, status: :limit_exceeded)
    end
    [ 2_097_151, 2_097_152, 2_097_153 ].each do |size|
      doc = Vault::Document.from_bytes("x".b * size)
      size <= 2_097_152 ? assert_equal(:unmanaged, doc.parse_status) : assert_code(:document_limit, doc, status: :limit_exceeded)
    end
  end

  def test_t25_production_depth_and_node_limits_before_append
    [ 15, 16, 17 ].each do |depth|
      doc = note("accio_schema: 1\nid: test\nx: " + "[" * (depth - 1) + "x" + "]" * (depth - 1))
      depth <= 16 ? assert(doc.valid_metadata?) : assert_code(:depth_limit, doc, status: :limit_exceeded)
      assert_operator doc.metrics.fetch(:depth, 0), :<=, 16
    end
    [ 4095, 4096, 4097 ].each do |nodes|
      total = nodes - 15 # root/base/extra=7 + eight nested sequence nodes
      arrays = 8.times.map do |i|
        count = total / 8 + (i < total % 8 ? 1 : 0)
        "[#{([ 'x' ] * count).join(',')}]"
      end
      doc = note("accio_schema: 1\nid: test\nx: [#{arrays.join(',')}]")
      nodes <= 4096 ? assert(doc.valid_metadata?, doc.diagnostics.inspect) : assert_code(:node_limit, doc, status: :limit_exceeded)
      assert_operator doc.metrics.fetch(:nodes), :<=, 4096
    end
    guard = Vault::Metadata::Guard.new(limits(nodes: 3))
    builder = Vault::Metadata::GuardedTreeBuilder.new(guard)
    error = assert_raises(Vault::Metadata::Rejected) { Psych::Parser.new(builder).parse("a: b\nc: d") }
    assert_equal :node_limit, error.code
    assert_equal 3, builder.nodes
    # A control without our guard retains five content nodes, including both keys.
    unguarded = Psych::TreeBuilder.new
    Psych::Parser.new(unguarded).parse("a: b\nc: d")
    assert_equal 4, unguarded.root.children.first.children.first.children.size
  end

  def test_t25_mapping_sequence_scalar_and_specific_byte_limits
    [ 255, 256, 257 ].each do |pairs|
      yaml = "accio_schema: 1\nid: test\n" + (1..(pairs - 2)).map { |i| "k#{i}: v" }.join("\n")
      doc = note(yaml)
      pairs <= 256 ? assert(doc.valid_metadata?) : assert_code(:mapping_limit, doc, status: :limit_exceeded)
    end
    [ 511, 512, 513 ].each do |items|
      doc = note("accio_schema: 1\nid: test\nx: [#{([ 'x' ] * items).join(',')}]")
      items <= 512 ? assert(doc.valid_metadata?) : assert_code(:sequence_limit, doc, status: :limit_exceeded)
    end
    [ [ :scalar_limit, "title", 8192 ], [ :id_limit, "id", 4096 ], [ :tag_limit, "tags", 256 ],
      [ :label_limit, "label", 1024 ], [ :key_limit, "key", 128 ] ].each do |code, field, max|
      [ max - 1, max, max + 1 ].each do |bytes|
        value = "x" * bytes
        yaml = case field
        when "id" then "accio_schema: 1\nid: #{value}"
        when "tags" then "accio_schema: 1\nid: test\ntags: [#{value}]"
        when "label" then "accio_schema: 1\nid: test\nlink_bindings: [{label: #{value}, target_id: x}]"
        when "key" then "accio_schema: 1\nid: test\n#{value}: x"
        else "accio_schema: 1\nid: test\n#{field}: #{value}"
        end
        doc = note(yaml)
        bytes <= max ? assert(doc.valid_metadata?, "#{field}:#{bytes}") : assert_code(code, doc, status: :limit_exceeded)
      end
    end
    assert note("accio_schema: 1\nid: test\ntitle: #{'é' * 4096}").valid_metadata?
    [ 18, 19, 20 ].each do |digits|
      doc = note("accio_schema: #{'9' * digits}\nid: test")
      digits <= 19 ? assert_code(:unsupported_schema, doc, status: :incompatible) : assert_code(:schema_limit, doc, status: :limit_exceeded)
    end
  end

  def test_t25_known_list_limits_include_duplicate_tags
    { "tags" => 128, "project_ids" => 256, "task_ids" => 256, "link_bindings" => 256 }.each do |name, max|
      [ max - 1, max, max + 1 ].each do |count|
        values = count.times.map do |i|
          name == "link_bindings" ? "{label: l#{i}, target_id: n}" : (name == "tags" ? "tag" : "id#{i}")
        end
        doc = note("accio_schema: 1\nid: test\n#{name}: [#{values.join(',')}]")
        count <= max ? assert(doc.valid_metadata?) : assert_code(:sequence_limit, doc, status: :limit_exceeded)
        assert_includes codes(doc), :duplicate_tag if name == "tags" && count <= max
      end
    end
  end

  def test_t26_exact_deadline_and_each_stage
    [ -0.000000001, 0, 0.000000001 ].each do |delta|
      ticks = 0
      clock = -> { ticks += 1; ticks == 1 ? 0 : 0.1 + delta }
      doc = note(clock: clock)
      delta.negative? ? assert(doc.valid_metadata?) : assert_code(:parse_timeout, doc, status: :limit_exceeded)
    end
    # Each numbered guard call can expire, including callbacks, inspection,
    # projection and final assembly. No expired result can report valid.
    calls = 0
    counting = -> { calls += 1; 0 }
    assert note(clock: counting).valid_metadata?
    (2..calls).each do |expiration|
      count = 0
      clock = -> { count += 1; count >= expiration ? 0.1 : 0 }
      assert_code(:parse_timeout, note(clock: clock), status: :limit_exceeded)
    end
    budget = Vault::Configuration.new(clock: -> { 0 }).budget
    budget.define_singleton_method(:check!) { raise Vault::LinuxFilesystem::Error.new(:timed_out) }
    assert_code(:parse_timeout, note(budget: budget), status: :limit_exceeded)
    parsed = Vault::Metadata.parse("accio_schema: 1\nid: test", kind: :note, budget: budget)
    assert_equal :limit_exceeded, parsed.status
    assert_nil parsed.metadata
    assert_includes codes(parsed), :parse_timeout
  end

  def test_t28_no_parser_for_read_failures_and_contract_validation
    [ :unconfigured, :invalid_configuration, :unsupported_platform, :unavailable, :blocked, :changed, :unreadable, :limit_exceeded, :ready ].each do |state|
      source = Vault::Result.new(state: state, code: :synthetic_failure, metrics: { bytes_read: 0 })
      Vault::Metadata.stub(:parse, ->(*) { flunk "parser reached for failed read" }) do
        doc = Vault::Document.from_read_result(source, kind: :note)
        assert_equal state, doc.read_state
        assert_equal :not_attempted, doc.parse_status
        assert_same source, doc.source_read_result
        assert_nil doc.raw_bytes
        assert_nil doc.local_classification
      end
    end
    bad = Vault::Result.new(state: :complete, data: { bytes: "x".b, sha256: "bad", path: "x.md" })
    assert_raises(ArgumentError) { Vault::Document.from_read_result(bad, kind: :note) }
    assert_raises(ArgumentError) { Vault::Document.from_bytes("x".b, kind: :other) }
  end

  def test_t29_no_io_loader_uuid_or_input_symbols
    # The canary is exercised as a negative control, then guards the actual path.
    canary = ->(*) { raise "forbidden API reached" }
    assert_raises(RuntimeError) { canary.call }
    File.stub(:open, canary) do
      File.stub(:read, canary) do
        Psych.stub(:parse, canary) do
          Psych.stub(:safe_load, canary) do
            assert note.valid_metadata?
            assert_code(:forbidden_tag, note("accio_schema: 1\nid: !!str test"))
          end
        end
      end
    end
    10.times { |i| note("accio_schema: 1\nid: test\nunknown#{i}: x") }
    before = Symbol.all_symbols.size
    300.times { |i| assert note("accio_schema: 1\nid: test\nunique_external_key_#{i}: x").valid_metadata? }
    assert_operator Symbol.all_symbols.size, :<=, before
    code = 'require "vault/document"; abort "database loaded" if defined?(Rails) || defined?(ActiveRecord) || $LOADED_FEATURES.any? { |feature| feature.include?("sqlite3") }'
    output, error, status = Open3.capture3(RbConfig.ruby, "-I", File.expand_path("../../../app/services", __dir__), "-e", code)
    assert status.success?, output + error
  end
end
