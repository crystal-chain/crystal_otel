# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.1] - 2026-06-30

### Fixed

- **Neo4j query spans now nest under the request span instead of detaching into orphan traces.** 0.4.0 instrumented the neo4j-ruby-driver's `Session#run`/`Transaction#run`, but the driver executes queries inside the `async` gem's reactor **Fiber**, and OpenTelemetry's `Context` is fiber-local — so the span was created with an empty context and started its own root trace. The instrumentation now hooks `ActiveGraph::Base.query_run` (the single funnel for raw `Base.query`, the query builder, and the ORM), which runs on the request thread/fiber where the controller span is still current, so `neo4j.query` spans correctly parent to the active span. Guard is now `defined?(ActiveGraph::Base)`.

## [0.4.0] - 2026-06-30

### Added

- **Neo4j query instrumentation.** Prepends a tracing wrapper onto `Neo4j::Driver::Internal::InternalSession#run` and `InternalTransaction#run` — the two methods every query funnels through — so raw Cypher (`session.run`), managed `read_transaction`/`write_transaction` blocks, the ActiveGraph query builder, and the ActiveGraph ORM all emit a client span (`db.system=neo4j`, obfuscated `db.statement`, `db.operation`). Spans nest under whatever span is active when the query runs, so they appear under the controller span (or a manual grouping span) automatically. Guarded by `defined?(Neo4j::Driver)`, so it is a no-op in services without Neo4j; toggle with `config.neo4j_tracing`. Query errors propagate exactly once, and any failure in span setup falls back to running the query untraced.
- **`CrystalOtel.trace(name, attributes:)` helper.** Opens a child span around an arbitrary block (e.g. a loop or service call) so application code shows up in the waterfall and auto-instrumented spans created inside it nest underneath. Falls back to running the block untraced when OpenTelemetry is unavailable or telemetry is disabled.

## [0.3.2] - 2026-06-30

### Fixed

- **Exception tracking now records exceptions.** The `ExceptionTracker` middleware was inserted after `ActionDispatch::RequestId`, placing it *outside* `ActionDispatch::ShowExceptions`/`DebugExceptions`. Those middlewares rescue unhandled exceptions and render an HTTP error response without re-raising, so the exception never propagated to the tracker and `span.record_exception` was never called — spans were marked errored (4xx/5xx) but carried no exception event. The tracker is now inserted after `ActionDispatch::DebugExceptions` so raised exceptions reach it and are recorded before Rails renders the error. `RequestMetrics` remains outermost (after `ActionDispatch::RequestId`) to time the full request.

## [0.3.1] - 2026-06-30

### Fixed

- **`http.request.body` / `http.response.body` "Encoding Error"** — `ControllerTracking` sanitized bodies with `String#encode("UTF-8", invalid: :replace, ...)`, which is a no-op when the string is already tagged UTF-8 (as Rails tags `raw_post` for JSON requests). Invalid bytes survived and broke OTLP serialization, so the body attribute exported as an encoding error. Bodies and the query string are now scrubbed via `force_encoding("UTF-8").scrub("?")`, which reliably replaces invalid byte sequences regardless of source encoding.

## [0.1.0] - 2025-06-29

### Added

- **Distributed tracing** via OpenTelemetry SDK with OTLP/HTTP export
- **Auto-instrumentation** for Rails, Rack, ActionPack, ActiveRecord, PostgreSQL, Redis, Sidekiq, Net::HTTP, Faraday, and concurrent-ruby
- **Metrics** — HTTP request duration histogram, active-requests counter, Ruby runtime gauges (GC count, thread count, RSS memory)
- **Business metrics DSL** — register application-defined counters (event-driven via ActiveSupport::Notifications) and gauges (polled on a 30-second interval)
- **Log correlation** — injects `trace_id` and `span_id` into every Rails log line when inside a valid span
- **Exception tracking middleware** — records unhandled exceptions and 4xx/5xx responses as span events/errors
- **Controller tracking concern** (`CrystalOtel::ControllerTracking`) — tags spans with controller, action, request/response metadata, and authenticated user ID
- **Kill-switch** — set `config.enabled = false` or `OTEL_ENABLED=false` to disable all instrumentation without removing the gem
- **Environment-aware defaults** — automatically disabled in the Rails test environment; enabled everywhere else
- **Configurable OTLP endpoint** via `OTEL_EXPORTER_OTLP_ENDPOINT` env var (default: `http://localhost:4318`)
- **Rails Engine** with ordered initializers so SDK setup runs after any other OTel-aware engines

[0.3.2]: https://github.com/crystal-chain/crystalchain_otel/releases/tag/v0.3.2
[0.4.1]: https://github.com/crystal-chain/crystalchain_otel/releases/tag/v0.4.1
[0.4.0]: https://github.com/crystal-chain/crystalchain_otel/releases/tag/v0.4.0
[0.3.1]: https://github.com/crystal-chain/crystalchain_otel/releases/tag/v0.3.1
[0.1.0]: https://github.com/crystal-chain/crystalchain_otel/releases/tag/v0.1.0
