# frozen_string_literal: true

module CrystalOtel
  module Instrumentation
    # Traces every Cypher query issued through ActiveGraph — raw
    # `ActiveGraph::Base.query(cypher)`, the query builder, and the ORM
    # persistence layer all funnel through `ActiveGraph::Base.query_run`
    # (defined by ActiveGraph::Core::Querable).
    #
    # We instrument `query_run` rather than the neo4j-ruby-driver's
    # `Session#run`/`Transaction#run` deliberately: the driver executes inside
    # the `async` gem's reactor **Fiber**, and OpenTelemetry's Context is
    # fiber-local, so a span created there has an empty context and detaches
    # into its own orphan trace. `query_run` runs on the request thread/fiber
    # (it only enters the reactor inside its own `transaction { tx.run }`
    # block), where the controller's span is still current — so spans created
    # here nest correctly under the controller (or under a manual
    # `CrystalOtel.trace(...)` span).
    module Neo4j
      MAX_STATEMENT_LENGTH = 2000

      # Prepended onto ActiveGraph::Base's singleton class. Bare `super`
      # forwards the original arguments and propagates any query error normally
      # (tracer.in_span records and re-raises it).
      module QueryRunInstrumentation
        def query_run(query, options = {})
          CrystalOtel::Instrumentation::Neo4j.trace_query(query) { super }
        end
      end

      module_function

      def install
        return if @installed
        return unless defined?(::ActiveGraph::Base)
        return unless ::ActiveGraph::Base.respond_to?(:query_run)

        ::ActiveGraph::Base.singleton_class.prepend(QueryRunInstrumentation)
        @installed = true
        Rails.logger.info("[CrystalOtel] Neo4j (ActiveGraph) instrumentation installed") if defined?(Rails)
        true
      end

      def installed?
        @installed == true
      end

      # Wraps the query execution in a client span. If anything in the span
      # setup fails, the query still runs untraced — tracing must never break a
      # DB call. The execution block itself is never wrapped in a rescue, so a
      # real query error propagates exactly once.
      def trace_query(query)
        return yield unless tracing_enabled?

        attributes = begin
          build_attributes(query)
        rescue StandardError
          nil
        end
        return yield if attributes.nil?

        tracer.in_span("neo4j.query", kind: :client, attributes: attributes) { yield }
      end

      def tracing_enabled?
        !!(defined?(OpenTelemetry) && CrystalOtel.configuration.neo4j_tracing)
      end

      def tracer
        OpenTelemetry.tracer_provider.tracer("crystal_otel.neo4j")
      end

      def build_attributes(query)
        text = statement_text(query)
        {
          "db.system" => "neo4j",
          "db.statement" => obfuscate(text).slice(0, MAX_STATEMENT_LENGTH),
          "db.operation" => operation(text)
        }.compact
      end

      # ActiveGraph passes a built query object (responds to #cypher); raw and
      # driver paths may pass a Query (#to_cypher / #text) or a plain String.
      def statement_text(query)
        if query.respond_to?(:cypher)
          query.cypher.to_s
        elsif query.respond_to?(:to_cypher)
          query.to_cypher.to_s
        elsif query.respond_to?(:text)
          query.text.to_s
        else
          query.to_s
        end
      end

      # Strips string-literal *contents* (the real PII risk) while keeping the
      # query structure. Numeric literals are left intact — LIMIT/SKIP values
      # are useful and not sensitive. ActiveGraph parameterizes values via
      # $params anyway, so most literals never appear in the text.
      def obfuscate(cypher)
        cypher
          .gsub(/'(?:[^'\\]|\\.)*'/, "'?'")
          .gsub(/"(?:[^"\\]|\\.)*"/, '"?"')
      end

      # First Cypher keyword (MATCH, CREATE, MERGE, …), used as db.operation.
      def operation(cypher)
        cypher[/\A\s*(\w+)/, 1]&.upcase
      end

      private_class_method :tracer, :build_attributes
    end
  end
end
