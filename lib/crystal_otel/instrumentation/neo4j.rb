# frozen_string_literal: true

module CrystalOtel
  module Instrumentation
    # Traces every Cypher query issued through ActiveGraph. Reads
    # (`QueryInterface`, the query builder via `Core::Query#response`) and
    # writes (`neo4j_query` in the persistence layer) all funnel through
    # `ActiveGraph::Base.query`.
    #
    # We hook `ActiveGraph::Base.query` and *not* a lower layer (the driver's
    # `Session#run`, or ActiveGraph's `query_run`) on purpose: the
    # neo4j-ruby-driver marks `run`/`begin_transaction`/`transaction` with
    # `sync`, which wraps them in the `async` gem's `Sync {}` — a reactor
    # **Fiber**. OpenTelemetry's `Context` is fiber-local, so any span created
    # at or below that boundary has an empty context and detaches into its own
    # orphan trace (this is why instrumenting the driver, and even `query_run`
    # which runs inside `query`'s `transaction(implicit:true)` block, failed).
    # `ActiveGraph::Base.query` is the outermost call and runs on the request
    # thread/fiber, before `transaction` enters `Sync {}`, so the controller's
    # span is still current and `neo4j.query` spans nest correctly under it (or
    # under a manual `CrystalOtel.trace(...)` span).
    #
    # That leaves one gap: queries issued *inside* an already-open transaction —
    # most notably the `after_save` cascade that `save` runs inside the implicit
    # transaction opened by ActiveGraph's `cascade_save`. Those run below the
    # `Sync {}` boundary with an empty context and orphan. `TransactionInstrumentation`
    # closes it by capturing the current context on the request fiber (before the
    # transaction enters `Sync {}`) and re-establishing it inside the transaction
    # block, so spans created there nest under the request trace. Same technique
    # report-gene's `Neo4j::Parallel` uses to carry context across threads.
    module Neo4j
      MAX_STATEMENT_LENGTH = 2000

      # Prepended onto ActiveGraph::Base's singleton class. Bare `super`
      # forwards the original arguments and propagates any query error normally
      # (tracer.in_span records and re-raises it).
      module QueryInstrumentation
        def query(*args)
          CrystalOtel::Instrumentation::Neo4j.trace_query(args.first) { super }
        end
      end

      # Prepended onto ActiveGraph::Base's singleton class. `send_transaction`
      # is the single funnel every transaction passes through — both `save`'s
      # `cascade_save` block and the implicit `transaction(implicit: true)`
      # wrapping each `query`. It is entered on the request fiber, *before*
      # `run_transaction_work` hands the block to the driver's `sync`-marked
      # `write_transaction`/`read_transaction` (the `Sync {}` boundary). We
      # capture the OpenTelemetry context here and re-establish it inside the
      # block via `Context.with_current`, so spans created below the fiber
      # boundary nest under the request trace instead of orphaning. Wrapping the
      # block (rather than opening a span) is a pure passthrough: `with_current`
      # returns the block's value, and errors/`ActiveGraph::Rollback` propagate
      # unchanged.
      module TransactionInstrumentation
        def send_transaction(method, **config, &block)
          return super unless block && CrystalOtel::Instrumentation::Neo4j.tracing_enabled?

          ctx = ::OpenTelemetry::Context.current
          wrapped = ->(tx) { ::OpenTelemetry::Context.with_current(ctx) { block.call(tx) } }
          super(method, **config, &wrapped)
        end
      end

      module_function

      def install
        return if @installed
        return unless defined?(::ActiveGraph::Base)
        return unless ::ActiveGraph::Base.respond_to?(:query)

        ::ActiveGraph::Base.singleton_class.prepend(QueryInstrumentation)
        ::ActiveGraph::Base.singleton_class.prepend(TransactionInstrumentation)
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

        frame = caller_frame
        attributes = begin
          build_attributes(query, frame)
        rescue StandardError
          nil
        end
        return yield if attributes.nil?

        tracer.in_span(span_name(frame), kind: :client, attributes: attributes) { yield }
      end

      def tracing_enabled?
        !!(defined?(OpenTelemetry) && CrystalOtel.configuration.neo4j_tracing)
      end

      def tracer
        OpenTelemetry.tracer_provider.tracer("crystal_otel.neo4j")
      end

      def build_attributes(query, frame = nil)
        text = statement_text(query)
        {
          "db.system" => "neo4j",
          "db.statement" => obfuscate(text).slice(0, MAX_STATEMENT_LENGTH),
          "db.operation" => operation(text),
          "code.function" => frame&.label,
          "code.filepath" => frame&.path,
          "code.lineno" => frame&.lineno
        }.compact
      end

      # Span name carries the application method that issued the query, e.g.
      # "neo4j.query ProductService#refresh". Falls back to the bare
      # "neo4j.query" when no application frame can be identified.
      def span_name(frame)
        label = frame&.label
        label ? "neo4j.query #{label}" : "neo4j.query"
      end

      # Walks the call stack for the first *application* frame — i.e. the code
      # that actually issued the query. Everything between here and the app is
      # gem-internal: this file (trace_query + the query prepend) and ActiveGraph
      # / neo4j-driver frames, all of which live under a `/gems/` path. Returns a
      # Thread::Backtrace::Location or nil; never raises, so caller lookup can
      # never break a DB call.
      def caller_frame
        caller_locations.find { |loc| app_frame?(loc) }
      rescue StandardError
        nil
      end

      def app_frame?(loc)
        path = loc.path
        return false if path.nil?
        return false if path == __FILE__

        !path.include?("/gems/")
      end

      # The first arg to ActiveGraph::Base.query is either a String (raw Cypher,
      # e.g. from QueryInterface) or an ActiveGraph::Core::Query (responds to
      # #to_cypher). Fall back through #cypher / #text / #to_s for safety.
      def statement_text(query)
        if query.respond_to?(:to_cypher)
          query.to_cypher.to_s
        elsif query.respond_to?(:cypher)
          query.cypher.to_s
        elsif query.respond_to?(:text)
          query.text.to_s
        else
          query.to_s
        end
      rescue StandardError
        query.to_s
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

      private_class_method :tracer, :build_attributes, :span_name, :caller_frame, :app_frame?
    end
  end
end
