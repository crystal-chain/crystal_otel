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
  config.enabled         = ENV.fetch("OTEL_ENABLED", "true") == "true"
  config.service_name    = ENV.fetch("OTEL_SERVICE_NAME", "my-service")
  config.service_version = ENV.fetch("OTEL_SERVICE_VERSION", nil)
  config.otlp_endpoint   = ENV.fetch("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")
  config.resource_attributes = {
    "deployment.environment" => ENV.fetch("OTEL_ENVIRONMENT", Rails.env.to_s),
    "service.namespace"      => "my-org"
  }
end
```

Include `CrystalOtel::ControllerTracking` in `ApplicationController` for automatic request/response span tagging:

```ruby
class ApplicationController < ActionController::API
  include CrystalOtel::ControllerTracking
end
```

## Configuration Reference

| Attribute | Env var | Default | Description |
|---|---|---|---|
| `enabled` | `OTEL_ENABLED` | `true` (disabled in test) | Master kill-switch |
| `service_name` | — | Rails app name (underscored) | OTel `service.name` |
| `service_version` | `APP_VERSION` | `nil` | OTel `service.version` |
| `otlp_endpoint` | `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4318` | Base URL of the OTLP collector |
| `log_correlation` | — | `true` | Inject trace/span IDs into logs |
| `exception_tracking` | — | `true` | Record exceptions as span events |
| `metrics_enabled` | — | `true` | Enable metrics export |
| `sidekiq_tracing` | — | `true` | Enable Sidekiq instrumentation |
| `resource_attributes` | — | `{}` | Extra OTel resource attributes |
| `instrumentations` | — | `{}` | Per-library instrumentation overrides |
| `propagators` | — | `[:tracecontext, :baggage]` | W3C propagation (default) |

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
    # The event payload may include :value (integer, defaults to 1) and :attributes (hash).
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

## Kill-Switch

Disable all instrumentation without touching code:

```bash
OTEL_ENABLED=false rails server
```

Or in the initializer:

```ruby
CrystalOtel.configure do |config|
  config.enabled = false
end
```

When disabled, no SDK is configured, no middleware is inserted, no background threads are started, and no log formatter is wrapped. The gem is present but entirely inert.

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## License

MIT — see [LICENSE](LICENSE).
