# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.0]: https://github.com/crystal-chain/crystalchain_otel/releases/tag/v0.1.0
