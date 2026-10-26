require_relative "../document"

module Vault
  class Metadata
    # A bounded, pure observation. Retains descriptions, never Documents/bodies.
    class IdentitySet
      Observation = Data.define(:scope, :entries, :coverage, :diagnostics, :text_bytes) do
        def apply(document)
          entry = entries.find { |item| item[:path] == document.path && item[:kind] == document.kind }
          raise ArgumentError, "document not in observation" unless entry && entry[:sha256] == document.source_sha256
          document.with_identity(entry.fetch(:identity_status), diagnostics: entry.fetch(:diagnostics))
        end
      end

      def self.describe(document, path: document.path)
        Metadata.immutable({ path: path, kind: document.kind, sha256: document.source_sha256,
          source_read_state: document.source_read_state, parse_status: document.parse_status,
          local_classification: document.local_classification, claimed_id: document.claimed_id })
      end

      def self.call(occurrences, scope:, complete:, parser_limits: Limits.new, budget: Configuration.new.budget)
        new(parser_limits, budget).call(occurrences, scope, complete)
      end

      def initialize(limits, budget)
        @limits, @budget = limits, budget
        @entries, @seen, @groups, @text_bytes = [], {}, {}, 0
        @diagnostics = Diagnostics.new(limits)
      end

      def call(occurrences, scope, complete)
        raise ArgumentError, "explicit scope and coverage required" unless scope.is_a?(String) && scope.valid_encoding? && scope.bytesize.between?(1, @limits[:id_bytes]) && [ true, false ].include?(complete)
        @coverage = { note: complete, folder: complete }
        consume(occurrences)
        finalize
        result = observation(scope)
        begin
          @budget.check!
        rescue LinuxFilesystem::Error => error
          raise unless [ :timed_out, :limit_exceeded ].include?(error.code)
          incomplete!(error.code)
          revoke_uniqueness!
          result = observation(scope)
        end
        result
      end

      private

      def observation(scope)
        Observation.new(scope.dup.freeze, Metadata.immutable(@entries.sort_by { |entry| [ entry[:path].b, entry[:kind].to_s ] }),
          Metadata.immutable(@coverage), @diagnostics.items, @text_bytes).freeze
      end

      def revoke_uniqueness!
        @entries.each do |entry|
          if entry[:identity_status] == :unique_in_observation
            entry[:identity_status] = :unverified
            entry[:diagnostics] << { code: :identity_incomplete, severity: :warning, domain: :identity }
          end
        end
      end

      def consume(occurrences)
        count = 0
        occurrences.each do |item|
          @budget.check!
          count += 1
          if count > @limits[:entries]
            incomplete!(:identity_limit)
            break
          end
          entry = description!(item)
          key = [ entry[:kind], entry[:path] ]
          if @seen[key]
            @coverage[entry[:kind]] = false
            @diagnostics.add(:inconsistent_observation, severity: :error, domain: :identity)
            next
          end
          size = entry[:path].bytesize + (entry[:claimed_id]&.bytesize || 0)
          if @text_bytes + size > @limits[:identity_bytes]
            incomplete!(:identity_limit)
            break
          end
          @text_bytes += size
          @seen[key] = true
          @entries << entry
          id = entry[:claimed_id]
          (@groups[[ entry[:kind], id ]] ||= []) << entry if id
          unless entry[:source_read_state] == :complete &&
              (entry[:parse_status] == :unmanaged || (id && [ :valid, :invalid ].include?(entry[:parse_status])))
            @coverage[entry[:kind]] = false
          end
        end
        @budget.check!
      rescue LinuxFilesystem::Error => error
        raise unless [ :timed_out, :limit_exceeded ].include?(error.code)
        incomplete!(error.code)
      end

      def description!(item)
        raise ArgumentError, "description required" unless item.is_a?(Hash)
        kind = item.fetch(:kind)
        raise ArgumentError, "unsupported kind" unless [ :note, :folder ].include?(kind)
        path = PathPolicy.new(Configuration.new).validate(item.fetch(:path))
        expected = kind == :note ? :markdown : :marker
        raise ArgumentError, "kind/path mismatch" unless PathPolicy.new(Configuration.new).candidate(path) == expected
        id = item[:claimed_id]
        raise ArgumentError, "invalid claim" unless id.nil? || (id.is_a?(String) && id.encoding == Encoding::UTF_8 &&
          id.valid_encoding? && id.bytesize <= @limits[:id_bytes] && !id.include?("\0") && !/\A[[:space:]]*\z/.match?(id))
        sha = item[:sha256]
        raise ArgumentError, "invalid checksum" unless sha.nil? || (sha.is_a?(String) && /\A[0-9a-f]{64}\z/.match?(sha))
        { kind: kind, path: path.dup, claimed_id: id&.dup, sha256: sha&.dup,
          source_read_state: item.fetch(:source_read_state), parse_status: item.fetch(:parse_status),
          local_classification: item.fetch(:local_classification), diagnostics: [] }
      end

      def incomplete!(code)
        @coverage.keys.each { |kind| @coverage[kind] = false }
        @diagnostics.add(code, severity: :error, domain: :identity)
      end

      def finalize
        @entries.each do |entry|
          conflict = entry[:claimed_id] && @groups.fetch([ entry[:kind], entry[:claimed_id] ]).size > 1
          entry[:identity_status] = if conflict then :conflicting
          elsif entry[:local_classification] == :managed && entry[:parse_status] == :valid
            @coverage[entry[:kind]] ? :unique_in_observation : :unverified
          else :not_applicable
          end
          entry[:classification] = conflict ? :identity_conflict : entry[:local_classification]
          code = conflict ? :identity_conflict : (@coverage[entry[:kind]] ? nil : :identity_incomplete)
          entry[:diagnostics] << { code: code, severity: conflict ? :error : :warning, domain: :identity } if code
        end
        # Expiration during finalization revokes EVERY tentative uniqueness claim.
        @budget.check!
      rescue LinuxFilesystem::Error => error
        raise unless [ :timed_out, :limit_exceeded ].include?(error.code)
        incomplete!(error.code)
        revoke_uniqueness!
      end
    end
  end
end
