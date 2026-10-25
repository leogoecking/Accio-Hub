require_relative "../../support/vault_service_test_helper"

class VaultReaderTest < VaultServiceTest
  def test_bytes_encoding_checksum_and_tree_are_preserved_without_parsing
    sandbox do |_base, vault|
      File.binwrite(File.join(vault, ".accio-folder.yml"), "!ruby/object:Inert {}\r\n")
      before = snapshot(vault)
      reader = Vault::Reader.new(vault_root(vault))
      %w[note.md .accio-folder.yml].each do |path|
        expected = File.binread(File.join(vault, path))
        result = reader.call(path)
        assert_equal :complete, result.state
        assert_equal expected, result.data.fetch(:bytes)
        assert_equal Encoding::BINARY, result.data.fetch(:bytes).encoding
        assert_equal Digest::SHA256.hexdigest(expected), result.data.fetch(:sha256)
        assert_equal expected.bytesize, result.metrics.fetch(:bytes_read)
      end
      assert_equal before, snapshot(vault)
    end
  end

  def test_unknown_regular_files_are_not_read
    sandbox do |_base, vault|
      File.write(File.join(vault, "unknown.bin"), "opaque")
      root = vault_root(vault, observer: ->(*) { flunk "unknown content reached adapter" })
      result = Vault::Reader.new(root).call("unknown.bin")
      assert_equal :blocked, result.state
      assert_equal :unsupported_content, result.code
    end
  end

  def test_real_unicode_case_and_component_byte_boundaries_preserve_distinct_names
    sandbox do |_base, vault|
      names = [ "ação.md", "ac\u0327a\u0303o.md", "Note.MD", "a" * 251 + ".md", "b" * 252 + ".md" ]
      names.each_with_index { |name, index| File.binwrite(File.join(vault, name), "synthetic-#{index}") }
      reader = Vault::Reader.new(vault_root(vault))
      names.each_with_index do |name, index|
        result = reader.call(name)
        assert_equal :complete, result.state
        assert_equal "synthetic-#{index}", result.data.fetch(:bytes)
      end
      over = reader.call("c" * 253 + ".md")
      assert_equal :blocked, over.state
      assert_equal :invalid_path, over.code
      assert_equal [ "note.md", *names ].map(&:b).sort, Dir.children(vault).map(&:b).sort
    end
  end

  def test_document_default_limit_minus_equal_plus_one
    sandbox do |_base, vault|
      limit = Vault::Configuration::DEFAULT_LIMITS.fetch(:document_bytes)
      reader = Vault::Reader.new(vault_root(vault))
      [ limit - 1, limit, limit + 1 ].each do |size|
        File.binwrite(File.join(vault, "note.md"), "x" * size)
        result = reader.call("note.md")
        if size <= limit
          assert_equal :complete, result.state
          assert_equal size, result.data.fetch(:bytes).bytesize
          assert_equal size, result.metrics.fetch(:bytes_read)
        else
          assert_equal :limit_exceeded, result.state
          assert_equal 0, result.metrics.fetch(:bytes_read)
          assert_empty result.data
        end
      end
    end
  end

  def test_shared_operation_budget_is_charged_for_each_read
    sandbox do |_base, vault|
      File.binwrite(File.join(vault, "note.md"), "1234")
      root = vault_root(vault, limits: { document_bytes: 4, operation_bytes: 8 })
      budget = root.configuration.budget
      reader = Vault::Reader.new(root)
      assert_equal :complete, reader.call("note.md", budget: budget).state
      assert_equal :complete, reader.call("note.md", budget: budget).state
      result = reader.call("note.md", budget: budget)
      assert_equal :limit_exceeded, result.state
      assert_equal 8, result.metrics.fetch(:bytes_read)
    end
  end

  def test_growth_or_truncation_after_a_chunk_discards_payload_and_keeps_actual_byte_count
    [ :grow, :truncate ].each do |mutation|
      sandbox do |_base, vault|
        chunk = Vault::LinuxFilesystem::Session::CHUNK
        File.binwrite(File.join(vault, "note.md"), "a" * (chunk + 1))
        once = false
        root = vault_root(vault, observer: lambda { |event, *|
          if event == :after_chunk && !once
            once = true
            mutate do
              File.binwrite(File.join(vault, "note.md"), mutation == :grow ? "b" * (chunk * 2) : "b")
            end
          end
        })
        result = Vault::Reader.new(root).call("note.md")
        assert_equal :changed, result.state
        assert_empty result.data
        assert_equal chunk, result.metrics.fetch(:bytes_read)
      end
    end
  end

  def test_deadline_exactly_at_limit_does_not_read_a_chunk
    sandbox do |_base, vault|
      now = 0.0
      root = vault_root(vault, clock: -> { now }, observer: ->(event, *) { now = 5.0 if event == :before_read })
      result = Vault::Reader.new(root).call("note.md")
      assert_equal :limit_exceeded, result.state
      assert_equal :timed_out, result.code
      assert_equal 0, result.metrics.fetch(:bytes_read)
      assert_empty result.data
    end
  end

  def test_links_specials_and_missing_files_never_become_successful_documents
    sandbox do |_base, vault, outside|
      File.link(File.join(outside, "note.md"), File.join(vault, "hard.md"))
      File.symlink("note.md", File.join(vault, "link.md"))
      File.mkfifo(File.join(vault, "fifo.md"), 0o600)
      reader = Vault::Reader.new(vault_root(vault))
      %w[hard.md link.md fifo.md].each do |name|
        result = reader.call(name)
        assert_equal :blocked, result.state
        assert_empty result.data
        assert_equal 0, result.metrics.fetch(:bytes_read)
      end
      assert_equal :unavailable, reader.call("missing.md").state
    end
  end

  def test_failed_read_still_charges_the_shared_budget_for_observed_bytes
    sandbox do |_base, vault|
      File.binwrite(File.join(vault, "note.md"), "1234")
      once = false
      root = vault_root(vault, limits: { document_bytes: 4, operation_bytes: 4 }, observer: lambda { |event, *|
        if event == :after_chunk && !once
          once = true
          mutate { File.binwrite(File.join(vault, "note.md"), "12") }
        end
      })
      budget = root.configuration.budget
      reader = Vault::Reader.new(root)
      changed = reader.call("note.md", budget: budget)
      assert_equal :changed, changed.state
      assert_equal 4, changed.metrics.fetch(:bytes_read)
      assert_equal :limit_exceeded, reader.call("note.md", budget: budget).state
      assert_equal 0, budget.remaining_bytes
    end
  end
end
