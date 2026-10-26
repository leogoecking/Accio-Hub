require "psych"
require_relative "limits"

module Vault
  class Metadata
    class GuardedTreeBuilder < Psych::TreeBuilder
      attr_reader :nodes, :max_depth

      def initialize(guard)
        super()
        @guard, @nodes, @documents, @depth, @max_depth = guard, 0, 0, 0, 0
      end

      def event_location(*)
        @guard.check!
        super
      end

      def start_document(version, directives, implicit)
        @guard.check!
        raise Rejected.new(:forbidden_directive) unless version.empty? && directives.empty?
        @documents += 1
        raise Rejected.new(:multiple_documents) if @documents > 1
        super
      end

      def start_mapping(anchor, tag, implicit, style)
        node!(anchor, tag, container: true)
        super
      end

      def start_sequence(anchor, tag, implicit, style)
        node!(anchor, tag, container: true)
        super
      end

      def end_mapping
        @guard.check!
        @depth -= 1
        super
      end

      def end_sequence
        @guard.check!
        @depth -= 1
        super
      end

      def scalar(value, anchor, tag, plain, quoted, style)
        @guard.limit!(:scalar_limit) if value.bytesize > @guard.limits[:scalar_bytes]
        node!(anchor, tag)
        super
      end

      def alias(_anchor)
        @guard.check!
        raise Rejected.new(:forbidden_alias)
      end

      private

      def node!(anchor, tag, container: false)
        @guard.check!
        raise Rejected.new(:forbidden_anchor) if anchor
        raise Rejected.new(:forbidden_tag) if tag
        @guard.limit!(:node_limit) if @nodes >= @guard.limits[:nodes]
        if @last.is_a?(Psych::Nodes::Mapping) && @last.children.size >= @guard.limits[:mapping] * 2
          @guard.limit!(:mapping_limit)
        elsif @last.is_a?(Psych::Nodes::Sequence) && @last.children.size >= @guard.limits[:sequence]
          @guard.limit!(:sequence_limit)
        end
        @guard.limit!(:depth_limit) if container && @depth >= @guard.limits[:depth]
        @nodes += 1
        if container
          @depth += 1
          @max_depth = [ @max_depth, @depth ].max
        end
      end
    end

    # YAML 1.2 Core resolution only; no Ruby ScalarScanner or object loader.
    def self.scalar_type(node)
      return :string unless node.is_a?(Psych::Nodes::Scalar) && node.plain
      case node.value
      when /\A(?:|~|null|Null|NULL)\z/ then :null
      when /\A(?:true|True|TRUE|false|False|FALSE)\z/ then :bool
      when /\A(?:[-+]?[0-9]+|0o[0-7]+|0x[0-9a-fA-F]+)\z/ then :int
      when /\A(?:[-+]?(?:\.[0-9]+|[0-9]+(?:\.[0-9]*)?)(?:[eE][-+]?[0-9]+)?|[-+]?\.(?:inf|Inf|INF)|\.(?:nan|NaN|NAN))\z/ then :float
      else :string
      end
    end

    class YamlParser
      attr_reader :maps, :metrics

      def initialize(guard)
        @guard, @maps, @metrics = guard, {}, {}
      end

      def call(yaml)
        @guard.precheck!(yaml)
        builder = GuardedTreeBuilder.new(@guard)
        Psych::Parser.new(builder).parse(yaml)
        @guard.check!
        root = builder.root.children.first&.children&.first
        raise Rejected.new(:wrong_type) unless root.is_a?(Psych::Nodes::Mapping)
        inspect_tree!(root)
        root
      ensure
        @metrics = { nodes: builder&.nodes || 0, depth: builder&.max_depth || 0 }.freeze
      end

      private

      def inspect_tree!(root)
        stack = [ root ]
        until stack.empty?
          @guard.check!
          node = stack.pop
          if node.is_a?(Psych::Nodes::Mapping)
            mapping = {}
            node.children.each_slice(2) do |key, value|
              @guard.check!
              raise Rejected.new(:complex_key) unless key.is_a?(Psych::Nodes::Scalar)
              name = key.value
              raise Rejected.new(:wrong_type) unless Metadata.scalar_type(key) == :string &&
                !/\A[[:space:]]*\z/.match?(name) && !/\p{Cc}/.match?(name)
              @guard.limit!(:key_limit) if name.bytesize > @guard.limits[:key_bytes]
              raise Rejected.new(:forbidden_merge) if name == "<<"
              raise Rejected.new(:duplicate_key) if mapping.key?(name)
              mapping[name] = value
              stack << value
            end
            @maps[node] = mapping
          elsif node.is_a?(Psych::Nodes::Sequence)
            stack.concat(node.children.reverse)
          end
        end
      end
    end
  end
end
