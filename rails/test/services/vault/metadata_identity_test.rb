require_relative "../../support/vault_metadata_test_helper"

class VaultMetadataIdentityTest < VaultMetadataTest
  def statuses(observation)
    observation.entries.to_h { |entry| [ entry[:path], entry[:identity_status] ] }
  end

  def test_t16_all_copies_conflict_independent_of_order_or_hash
    a = description(path: "a.md")
    b = description(note("accio_schema: 1\nid: test", "different"), path: "sub/b.md")
    [ [ a, b ], [ b, a ], [ a, a.merge(path: "b.md") ] ].each do |input|
      observed = observe(input)
      assert observed.entries.all? { |entry| entry[:identity_status] == :conflicting }
      assert observed.entries.all? { |entry| entry[:classification] == :identity_conflict }
      assert observed.entries.all? { |entry| entry[:local_classification] == :managed }
    end
    assert_equal observe([ a, b ]), observe([ b, a ])
  end

  def test_t17_namespaces_distinct_content_basename_and_literal_ids
    entries = [ description(path: "a.md"), description(marker("accio_schema: 1\nid: test"), path: ".accio-folder.yml"),
      description(note("accio_schema: 1\nid: other"), path: "sub/a.md") ]
    observed = observe(entries)
    assert observed.coverage.values.all?
    assert_equal [ :unique_in_observation ], observed.entries.map { |e| e[:identity_status] }.uniq
    [ [ "é", "é" ], [ "A", "a" ], [ "x", " x" ] ].each do |ids|
      entries = ids.each_with_index.map { |id, index| description(note("accio_schema: 1\nid: #{JSON.generate(id)}"), path: "#{index}.md") }
      assert observe(entries).entries.all? { |e| e[:identity_status] == :unique_in_observation }
    end
  end

  def test_t18_conservative_claim_and_incomplete_coverage
    good = description
    bad = note("accio_schema: 1\nid: test\nfavorite: bad")
    assert_equal "test", bad.claimed_id
    assert observe([ good, description(bad, path: "bad.md") ]).entries.all? { |e| e[:identity_status] == :conflicting }
    future = note("accio_schema: 2\nid: test")
    observed = observe([ good, description(future, path: "future.md"), description(note("accio_schema: 1\nid: other"), path: "other.md") ])
    refute observed.coverage[:note]
    assert_equal :conflicting, statuses(observed)["a.md"]
    assert_equal :unverified, statuses(observed)["other.md"]
    [ note("accio_schema: 1\nid: test\nid: bad"), note("accio_schema: 1\nid: !local test"), note("accio_schema: 1") ].each do |doc|
      assert_nil doc.claimed_id
      observed = observe([ good, description(doc, path: "bad.md") ])
      refute observed.coverage[:note]
      assert_equal :unverified, statuses(observed)["a.md"]
    end
    unmanaged = description(note("id: test"), path: "external.md")
    assert_equal :unique_in_observation, statuses(observe([ good, unmanaged ]))["a.md"]
  end

  def test_t19_partial_budgets_duplicates_and_bounded_enumeration
    good = description
    assert_equal :unverified, statuses(observe([ good ], complete: false))["a.md"]
    duplicate = observe([ good, good ])
    assert_equal 1, duplicate.entries.size
    assert_includes codes(duplicate), :inconsistent_observation
    assert_equal :unverified, statuses(duplicate)["a.md"]
    [ :unreadable, :changed, :limit_exceeded ].each do |state|
      failed = Vault::Document.from_read_result(Vault::Result.new(state: state), kind: :note)
      observed = observe([ good, Vault::Metadata::IdentitySet.describe(failed, path: "bad.md") ])
      assert_equal :unverified, statuses(observed)["a.md"]
    end
    observed = observe([ good, description(path: "b.md") ], parser_limits: limits(entries: 1))
    refute observed.coverage[:note]
    assert_equal 1, observed.entries.size
    bytes = good[:path].bytesize + good[:claimed_id].bytesize
    assert observe([ good ], parser_limits: limits(identity_bytes: bytes)).coverage[:note]
    refute observe([ good ], parser_limits: limits(identity_bytes: bytes - 1)).coverage[:note]
    enumerator = Enumerator.new { |y| loop { y << good } }
    bounded = observe(enumerator, parser_limits: limits(entries: 3))
    assert_includes codes(bounded), :identity_limit
    assert_equal 1, bounded.entries.size
    budget = Object.new
    budget.define_singleton_method(:check!) { raise Vault::LinuxFilesystem::Error.new(:timed_out) }
    assert_empty observe([ good ], budget: budget).entries
    refute observe([ good ], budget: budget).coverage[:note]
    ticks = 0
    budget.define_singleton_method(:check!) do
      ticks += 1
      raise Vault::LinuxFilesystem::Error.new(:timed_out) if ticks >= 3
    end
    observed = observe([ good ], budget: budget)
    assert_equal :unverified, statuses(observed)["a.md"]
  end

  def test_t20_move_and_reoccupied_path
    moved = observe([ description(path: "new/name.md") ])
    assert_equal "test", moved.entries.first[:claimed_id]
    assert_equal :unique_in_observation, moved.entries.first[:identity_status]
    replaced = observe([ description(note("accio_schema: 1\nid: replacement")) ])
    assert_equal "replacement", replaced.entries.first[:claimed_id]
  end

  def test_t21_folder_collisions_invalid_marker_and_separate_coverage
    same = marker("accio_schema: 1\nid: f\nparent_id: misleading\nname: other")
    assert same.valid_metadata?
    assert_equal [ "accio_schema", "id" ], same.present_fields
    entries = [ description(same, path: ".accio-folder.yml"), description(same, path: "sub/.accio-folder.yml"), description ]
    observed = observe(entries)
    assert_equal 2, observed.entries.count { |e| e[:identity_status] == :conflicting }
    observed = observe([ description(marker("id: bad"), path: ".accio-folder.yml"), description ])
    refute observed.coverage[:folder]
    assert observed.coverage[:note]
    assert_equal :unique_in_observation, statuses(observed)["a.md"]
    assert_nil marker("id: bad").metadata
  end

  def test_t29_description_retention_and_immutability
    doc = note
    input = description(doc)
    observed = observe([ input ])
    input[:path].replace("changed.md")
    assert_equal "a.md", observed.entries.first[:path]
    assert_raises(FrozenError) { observed.entries.first[:path].replace("x") }
    assert_raises(FrozenError) { observed.coverage[:note] = false }
    assert_raises(FrozenError) { observed.entries << {} }
    noisy = note("accio_schema: 1\nid: test\n" + (1..40).map { |i| "x#{i}: value" }.join("\n"))
    conflicted = noisy.with_identity(:conflicting, diagnostics: [ { code: :identity_conflict, severity: :error, domain: :identity } ])
    assert_equal 32, conflicted.diagnostics.size
    assert_includes codes(conflicted), :identity_conflict
    assert_equal :identity_conflict, conflicted.classification
    refute_includes observed.entries.first.keys, :raw_bytes
    refute_includes observed.entries.first.keys, :metadata
    refute_includes observed.entries.first.values, doc
    doc = Vault::Document.from_bytes("---\naccio_schema: 1\nid: test\n---\n".b)
    observed = observe([ Vault::Metadata::IdentitySet.describe(doc) ])
    assert_equal :unique_in_observation, observed.apply(doc).identity_status
    assert_equal :unverified, doc.identity_status
    assert_raises(ArgumentError) { observed.apply(note("accio_schema: 1\nid: changed")) }
  end
end
