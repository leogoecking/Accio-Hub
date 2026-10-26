require_relative "../../support/vault_service_test_helper"
require_relative "../../support/vault_metadata_test_helper"

class VaultMetadataIntegrationTest < VaultServiceTest
  def test_t30_synthetic_inventory_reader_document_identity_serializer_no_effects
    sandbox do |_base, vault|
      raw = "\xEF\xBB\xBF---\r\naccio_schema: 1\nid: repeated\ntags: [estudo, estudo, Estudo]\ncreated_at: 2026-01-02T00:00:00Z\nupdated_at: 2026-01-01T00:00:00Z\n# kept\r\n---\r\n<script>inert</script>\r\n".b
      File.binwrite(File.join(vault, "note.md"), raw)
      File.binwrite(File.join(vault, "copy.md"), raw)
      File.binwrite(File.join(vault, "unique.md"), "---\naccio_schema: 1\nid: unique\n---\nbody".b)
      File.binwrite(File.join(vault, ".accio-folder.yml"), "accio_schema: 1\nid: folder\nicon: unknown".b)
      before = snapshot(vault)
      root = vault_root(vault)
      budget = root.configuration.budget
      inventory = Vault::Inventory.new(root).call
      assert_equal :complete, inventory.state
      reader = Vault::Reader.new(root)
      documents = inventory.data.fetch(:entries).map do |entry|
        kind = { markdown: :note, marker: :folder }.fetch(entry.fetch(:candidate))
        read = reader.call(entry.fetch(:path), budget: budget)
        doc = Vault::Document.from_read_result(read, kind: kind, budget: budget)
        assert doc.valid_metadata?
        assert_equal read.metrics[:bytes_read], budget.bytes_read
        doc
      end
      observed = Vault::Metadata::IdentitySet.call(documents.map { |doc| Vault::Metadata::IdentitySet.describe(doc) },
        scope: "synthetic", complete: inventory.state == :complete, budget: budget)
      serializer = Vault::Serializer.new
      documents.each do |doc|
        assert_equal doc.raw_bytes, serializer.original(doc).bytes
        resolved = observed.apply(doc)
        if doc.claimed_id == "repeated"
          assert_equal :conflicting, resolved.identity_status
          assert_equal :identity_conflict, resolved.classification
          refute serializer.replace_body(resolved, "new").accepted?
          assert_includes resolved.diagnostics.map { |d| d[:code] }, :date_order_anomaly
          assert_includes resolved.diagnostics.map { |d| d[:code] }, :duplicate_tag
          assert serializer.replace_body(doc, doc.raw_body).accepted? # R1 unverified draft only
        elsif doc.kind == :note
          assert_equal :unique_in_observation, resolved.identity_status
          assert_equal doc.raw_bytes, serializer.replace_body(resolved, doc.raw_body).bytes
        end
      end
      assert_equal documents.sum { |doc| doc.raw_bytes.bytesize }, budget.bytes_read
      assert_equal before, snapshot(vault)
    end
  end

  def test_t28_reader_guards_links_specials_unreadable_and_changed_before_parser
    sandbox do |_base, vault, outside|
      File.link(File.join(outside, "note.md"), File.join(vault, "hard.md"))
      File.symlink("note.md", File.join(vault, "link.md"))
      File.mkfifo(File.join(vault, "fifo.md"), 0o600)
      File.binwrite(File.join(vault, "denied.md"), "synthetic")
      File.chmod(0, File.join(vault, "denied.md"))
      reader = Vault::Reader.new(vault_root(vault))
      Vault::Metadata.stub(:parse, ->(*) { flunk "parser reached after refused IO" }) do
        %w[hard.md link.md fifo.md denied.md missing.md].each do |path|
          read = reader.call(path)
          refute_equal :complete, read.state
          doc = Vault::Document.from_read_result(read, kind: :note)
          assert_equal read.state, doc.read_state
          assert_equal :not_attempted, doc.parse_status
          assert_nil doc.raw_bytes
        end
      end
    end
  end
end
