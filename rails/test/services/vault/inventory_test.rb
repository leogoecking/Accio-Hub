require_relative "../../support/vault_service_test_helper"

class VaultInventoryTest < VaultServiceTest
  def test_inventory_lists_hidden_unknowns_and_candidates_without_reading_bodies
    sandbox do |_base, vault|
      Dir.mkdir(File.join(vault, ".config"))
      File.binwrite(File.join(vault, ".config", "plugin.rb"), "raise 'INERT'")
      File.binwrite(File.join(vault, ".accio-folder.yml"), "opaque YAML")
      File.binwrite(File.join(vault, "unknown.bin"), "opaque")
      before = snapshot(vault)
      root = vault_root(vault, observer: ->(event, *) { flunk "inventory read content" if event == :after_chunk })
      result = Vault::Inventory.new(root).call
      assert_equal :complete, result.state
      entries = result.data.fetch(:entries)
      assert_equal [ ".accio-folder.yml", ".config", ".config/plugin.rb", "note.md", "unknown.bin" ], entries.map { |entry| entry.fetch(:path) }
      assert_equal :marker, entries.first.fetch(:candidate)
      refute entries.any? { |entry| entry.key?(:sha256) || entry.key?(:bytes) }
      assert_equal 0, result.metrics.fetch(:bytes_read)
      assert_equal before, snapshot(vault)
    end
  end

  def test_links_specials_hardlinks_and_invalid_names_produce_partial_diagnostics
    sandbox do |_base, vault, outside|
      File.link(File.join(outside, "note.md"), File.join(vault, "hard.md"))
      File.symlink(outside, File.join(vault, "linked"))
      File.mkfifo(File.join(vault, "fifo"), 0o600)
      File.binwrite(File.join(vault, "NUL.md"), "reserved")
      File.binwrite(File.join(vault.b, "bad\xff.md".b), "invalid name")
      result = Vault::Inventory.new(vault_root(vault)).call
      assert_equal :partial, result.state
      entries = result.data.fetch(:entries)
      assert_equal 6, entries.length
      assert_equal 5, result.data.fetch(:counts).fetch(:blocked)
      assert_equal [ :hardlink, :invalid_path, :special_file, :symlink ], entries.filter_map { |entry| entry[:code] }.uniq.sort
      assert_equal 0, result.metrics.fetch(:bytes_read)
    end
  end

  def test_unreadable_directory_is_partial_without_permission_changes
    sandbox do |_base, vault|
      secret = File.join(vault, "private")
      Dir.mkdir(secret)
      File.write(File.join(secret, "note.md"), "synthetic")
      File.chmod(0o000, secret)
      result = Vault::Inventory.new(vault_root(vault)).call
      assert_equal :partial, result.state
      entry = result.data.fetch(:entries).find { |item| item.fetch(:path) == "private" }
      assert_equal :unreadable, entry.fetch(:state)
      assert_equal 0, File.stat(secret).mode & 0o777
      assert_equal 2, result.metrics.fetch(:entries)
    ensure
      File.chmod(0o700, secret) if secret && File.exist?(secret) # Fixture cleanup only.
    end
  end

  def test_entry_limit_minus_equal_plus_one_counts_all_types
    sandbox do |_base, vault|
      inventory = Vault::Inventory.new(vault_root(vault, limits: { entries: 3 }))
      File.write(File.join(vault, "unknown"), "x")
      assert_equal :complete, inventory.call.state
      File.symlink("note.md", File.join(vault, "link"))
      equal = inventory.call
      assert_equal :partial, equal.state # Link blocked, but enumeration is complete.
      assert_nil equal.code
      assert_equal 3, equal.metrics.fetch(:entries)
      File.write(File.join(vault, ".fourth"), "x")
      over = inventory.call
      assert_equal :partial, over.state
      assert_equal :entry_limit, over.code
      assert_equal 3, over.metrics.fetch(:entries)
    end
  end

  def test_depth_allows_files_at_eight_and_blocks_ninth_directory_without_descending
    sandbox do |_base, vault|
      parent = vault
      9.times do |index|
        parent = File.join(parent, "d#{index + 1}")
        Dir.mkdir(parent)
        File.write(File.join(parent, "level.md"), "synthetic")
      end
      result = Vault::Inventory.new(vault_root(vault)).call
      assert_equal :partial, result.state
      entries = result.data.fetch(:entries)
      assert entries.any? { |entry| entry[:path] == "d1/d2/d3/d4/d5/d6/d7/level.md" && entry[:state] == :complete }
      assert entries.any? { |entry| entry[:path] == "d1/d2/d3/d4/d5/d6/d7/d8/level.md" && entry[:state] == :complete }
      assert entries.any? { |entry| entry[:path] == "d1/d2/d3/d4/d5/d6/d7/d8/d9" && entry[:state] == :limit_exceeded }
      refute entries.any? { |entry| entry[:path].end_with?("d9/level.md") }
    end
  end

  def test_oversize_candidate_is_diagnostic_unknown_large_file_remains_metadata_only
    sandbox do |_base, vault|
      File.binwrite(File.join(vault, "note.md"), "x" * 5)
      File.binwrite(File.join(vault, "unknown.bin"), "x" * 5)
      result = Vault::Inventory.new(vault_root(vault, limits: { document_bytes: 4 })).call
      assert_equal :partial, result.state
      entries = result.data.fetch(:entries).to_h { |entry| [ entry[:path], entry ] }
      assert_equal :document_limit, entries.fetch("note.md").fetch(:code)
      assert_equal :complete, entries.fetch("unknown.bin").fetch(:state)
      assert_equal 0, result.metrics.fetch(:bytes_read)
    end
  end

  def test_cooperative_deadline_preserves_partial_counts_without_accepted_content
    sandbox do |_base, vault|
      now = 0.0
      root = vault_root(vault, clock: -> { now }, observer: ->(event, path, *) { now = 5.0 if event == :pinned && path == "note.md" })
      result = Vault::Inventory.new(root).call
      assert_equal :partial, result.state
      assert_equal :timed_out, result.code
      assert_equal 1, result.metrics.fetch(:entries)
      assert_equal 0, result.metrics.fetch(:bytes_read)
    end
  end

  def test_deadline_reached_while_building_final_result_is_not_reported_complete
    sandbox do |_base, vault|
      File.unlink(File.join(vault, "note.md"))
      calls = 0
      root = vault_root(vault, clock: -> { calls += 1; calls >= 4 ? 5.0 : 0.0 })
      result = Vault::Inventory.new(root).call
      assert_equal :partial, result.state
      assert_equal :timed_out, result.code
      assert_equal 0, result.metrics.fetch(:entries)
    end
  end

  def test_entry_disappearance_never_turns_into_an_empty_successful_inventory
    sandbox do |_base, vault|
      once = false
      root = vault_root(vault, observer: lambda { |event, path, *|
        if event == :pinned && path == "note.md" && !once
          once = true
          mutate { File.unlink(File.join(vault, "note.md")) }
        end
      })
      result = Vault::Inventory.new(root).call
      refute result.success?
      assert_includes [ :changed, :partial ], result.state
      assert_equal 0, result.metrics.fetch(:bytes_read)
    end
  end
end
