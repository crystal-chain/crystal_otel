# crystal_otel

OpenTelemetry instrumentation gem for Crystal Chain Rails applications. Provides distributed tracing, metrics, log correlation, and exception tracking with minimal configuration.

## Features

- Distributed tracing with OTLP/HTTP export
- Auto-instrumentation for Rails, Rack, ActionPack, ActiveRecord, PG, Redis, Sidekiq, Net::HTTP, Faraday, concurrent-ruby
- HTTP request duration and active-request metrics
- Ruby runtime metrics (GC, threads, RSS memory)
- Business metrics DSL (counters + gauges)
- Trace ID / Span ID injected into every log line
- Exception and error-status tracking middleware
- Controller tracking concern
- Kill-switch env var for instant disable

## Installation

Add the GitHub Packages source to your `Gemfile`:

```ruby
source "https://rubygems.pkg.github.com/crystal-chain" do
  gem "crystal_otel", "~> 0.1"
end
```

Configure Bundler to authenticate against GitHub Packages. Add to `~/.bundle/config` or set as an environment variable:

```
BUNDLE_RUBYGEMS__PKG__GITHUB__COM=<github-username>:<personal-access-token>
```

The token needs `read:packages` scope.

## Quick Start

Create `config/initializers/crystal_otel.rb`:

```ruby
CrystalOtel.configure do |config|
  config.service_name = ENV.fetch("OTEL_SERVICE_NAME", "my-service")
end
```

That's the minimum. Everything else resolves from env vars or sensible defaults. Include `CrystalOtel::ControllerTracking` in `ApplicationController` for automatic request/response span tagging:

```ruby
class ApplicationController < ActionController::API
  include CrystalOtel::ControllerTracking
end
```

## Configuration Reference

### Core

| Attribute | Env var | Default | Description |
|---|---|---|---|
| `service_name` | `OTEL_SERVICE_NAME` | Rails app name (underscored) | OTel `service.name` |
| `service_version` | `APP_VERSION` | `nil` | OTel `service.version` |
| `otlp_endpoint` | `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4318` | Base URL of the OTLP collector (no path suffix) |
| `resource_attributes` | `OTEL_RESOURCE_ATTRIBUTES` | `{}` | Extra OTel resource attributes — see below |

### Feature flags

| Attribute | Default | Description |
|---|---|---|
| `enabled` | `true` (auto-`false` in test) | Enable/disable the gem programmatically |
| `log_correlation` | `true` | Inject `trace_id`/`span_id` into every log line |
| `exception_tracking` | `true` | Record unhandled exceptions as span events |
| `metrics_enabled` | `true` | Enable runtime and business metrics export |
| `sidekiq_tracing` | `true` | Enable Sidekiq auto-instrumentation |
| `instrumentations` | `{}` | Per-library instrumentation overrides (merged on top of defaults) |
| `propagators` | `[:tracecontext, :baggage]` | W3C trace-context propagation |

### Kill-switches

Two independent ways to disable all instrumentation. Either is sufficient; `CRYSTAL_OTEL_DISABLED` takes precedence over everything else.

| Mechanism | How |
|---|---|
| `CRYSTAL_OTEL_DISABLED=true` | Env var — no code change needed, works in any environment |
| `config.enabled = false` | Initializer — evaluated after boot |

When disabled, no SDK is configured, no middleware is inserted, no background threads are started, and no log formatter is wrapped. The gem is present but entirely inert.

### Sampling

| Attribute | Env var | Default | Description |
|---|---|---|---|
| `sampling_ratio` | `OTEL_TRACES_SAMPLER_ARG` | `1.0` | Fraction of traces to sample (`0.0`–`1.0`). Values < 1.0 activate parent-based ratio sampling automatically. |

```bash
# Sample 10 % of traces
OTEL_TRACES_SAMPLER_ARG=0.1 rails server
```

If `OTEL_TRACES_SAMPLER` is already set in the environment the gem won't override it, so you can use any sampler the OTel SDK supports directly.

### Batch span processor tuning

These mirror the standard OTel SDK env vars. Adjust for high-throughput services to avoid queue pressure.

| Attribute | Env var | Default | Description |
|---|---|---|---|
| `batch_max_queue_size` | `OTEL_BSP_MAX_QUEUE_SIZE` | `2048` | Max spans buffered before export |
| `batch_schedule_delay_ms` | `OTEL_BSP_SCHEDULE_DELAY` | `5000` | Export interval in milliseconds |
| `batch_max_export_batch_size` | `OTEL_BSP_MAX_EXPORT_BATCH_SIZE` | `512` | Max spans per export request |

### Resource attributes

Resource attributes identify the service in every signal (traces, metrics, logs). Two ways to set them:

**Via `OTEL_RESOURCE_ATTRIBUTES`** (standard OTel env var, works across all OTel SDKs):

```bash
OTEL_RESOURCE_ATTRIBUTES=service.namespace=crystalcollect,team=platform rails server
```

**Via the initializer** (merges on top of the env var; initializer values win on conflict):

```ruby
CrystalOtel.configure do |config|
  config.resource_attributes = {
    "deployment.environment" => ENV.fetch("OTEL_ENVIRONMENT", Rails.env.to_s),
    "service.namespace"      => "crystalcollect"
  }
end
```

## Auto-Instrumented Libraries

| Library | Gem |
|---|---|
| Rails | `opentelemetry-instrumentation-rails` |
| Rack | `opentelemetry-instrumentation-rack` |
| ActionPack | `opentelemetry-instrumentation-action_pack` |
| ActiveRecord | `opentelemetry-instrumentation-active_record` |
| PostgreSQL | `opentelemetry-instrumentation-pg` |
| Redis | `opentelemetry-instrumentation-redis` |
| Sidekiq | `opentelemetry-instrumentation-sidekiq` |
| Net::HTTP | `opentelemetry-instrumentation-net_http` |
| Faraday | `opentelemetry-instrumentation-faraday` |
| concurrent-ruby | `opentelemetry-instrumentation-concurrent_ruby` |

Health-check paths (`/healthz`, `/health`, `/up`, `/api/v1/healthz`) are excluded from Rack traces. SQL and Redis statements are obfuscated by default.

## Business Metrics DSL

Register application-defined metrics in your initializer:

```ruby
CrystalOtel.configure do |config|
  config.business_metrics do |m|
    # Counter: incremented each time the named ActiveSupport::Notifications event fires.
    # Payload may include :value (integer, defaults to 1) and :attributes (hash).
    m.counter "product.submissions",
              description: "Product data submissions",
              event:       "product.data.submitted"

    # Gauge: polled every 30 seconds; callback must return an integer or a Hash
    # (Hash keys become the "category" attribute on the recorded value).
    m.gauge "users.active",
            description: "Active users",
            callback:    -> { User.where(active: true).count }
  end
end
```

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
gem build crystal_otel.gemspec
```

## License

MIT — see [LICENSE](LICENSE).
