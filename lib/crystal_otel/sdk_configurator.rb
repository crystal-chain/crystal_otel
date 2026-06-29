# frozen_string_literal: true

require "opentelemetry/sdk"
require "opentelemetry-exporter-otlp"

module CrystalOtel
  # Responsible for initializing the OpenTelemetry SDK for both traces and metrics.
  # Called from the Engine initializer rather than directly from application code.
  #
  # The Engine runs this *after* the "opentelemetry.configure" initializer so that
  # any upstream Rails engines that register their own OTel config have already run.
  # Running before that hook would cause the SDK to be configured twice, with the
  # second call resetting instrumentation registered by the first.
  module SdkConfigurator
    module_function

    # Entry point: sets up traces and, when enabled, metrics.
    # Returns early if the gem is disabled (e.g. in test environments).
    def setup!
      config = CrystalOtel.configuration
      return unless config.enabled?

      configure_traces(config)
      configure_metrics(config) if config.metrics_enabled
    end

    # Configures the OpenTelemetry trace SDK: service identity, resource attributes,
    # a batching OTLP exporter, and all auto-instrumentation libraries via +use_all+.
    # Instrumentation options merge user-supplied overrides on top of the gem defaults
    # (see +build_instrumentation_config+).
    def configure_traces(config)
      OpenTelemetry::SDK.configure do |c|
        c.service_name = config.resolved_service_name
        c.service_version = config.service_version if config.service_version

        c.resource = OpenTelemetry::SDK::Resources::Resource.create(
          build_resource_attributes(config)
        )

        # Configure OTLP exporter for traces
        c.add_span_processor(
          OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
            OpenTelemetry::Exporter::OTLP::Exporter.new(
              endpoint: "#{config.otlp_endpoint}/v1/traces"
            )
          )
        )

        c.use_all(build_instrumentation_config(config))
      end
    end

    # Bootstraps the metrics SDK independently of the trace SDK.
    # Metrics gems are required lazily here so that apps which set
    # +metrics_enabled = false+ don't need them in their Gemfile.
    # Exports on a 60-second interval with a 30-second per-export timeout.
    # Assigns the resulting MeterProvider to +OpenTelemetry.meter_provider+
    # so that business and runtime metric code can obtain meters without
    # needing a direct reference to this module.
    def configure_metrics(config)
      require "opentelemetry-metrics-sdk"
      require "opentelemetry-exporter-otlp-metrics"

      metric_exporter = OpenTelemetry::Exporter::OTLP::Metrics::MetricsExporter.new(
        endpoint: "#{config.otlp_endpoint}/v1/metrics"
      )

      metric_reader = OpenTelemetry::SDK::Metrics::Export::PeriodicMetricReader.new(
        exporter: metric_exporter,
        export_interval_millis: 60_000,
        export_timeout_millis: 30_000
      )

      resource = OpenTelemetry::SDK::Resources::Resource.create(
        build_resource_attributes(config)
      )
      OpenTelemetry.meter_provider = OpenTelemetry::SDK::Metrics::MeterProvider.new(resource: resource)
      OpenTelemetry.meter_provider.add_metric_reader(metric_reader)
    end

    # Builds the OTel resource attribute hash from config plus the current Rails env.
    # Nil values are dropped so the SDK doesn't receive empty string attributes for
    # optional fields like service_version that may not be set in all environments.
    def build_resource_attributes(config)
      attrs = {
        "service.name" => config.resolved_service_name,
        "service.version" => config.service_version,
        "deployment.environment" => (defined?(Rails) ? Rails.env.to_s : "unknown")
      }
      attrs.merge!(config.resource_attributes)
      attrs.each_with_object({}) do |(k, v), h|
        h[k] = v.to_s unless v.nil?
      end
    end

    # Merges gem-level instrumentation defaults with any per-instrumentation
    # overrides supplied by the application via +config.instrumentations+.
    # Application values win on conflict, allowing selective opt-out or
    # reconfiguration of individual libraries without replacing the full hash.
    #
    # Notable defaults:
    # - Health-check paths are excluded from Rack traces to reduce noise.
    # - SQL and Redis statements are obfuscated, not omitted, to preserve
    #   query shapes in traces while avoiding PII/credential leakage.
    # - Sidekiq spans are linked as children (not continuations) so the
    #   enqueue span and the execute span remain in the same trace.
    def build_instrumentation_config(config)
      defaults = {
        "OpenTelemetry::Instrumentation::Rack" => {
          untraced_endpoints: [ "/api/v1/healthz", "/healthz", "/health", "/up" ]
        },
        "OpenTelemetry::Instrumentation::ActionPack" => {
          span_naming: :class # Use Controller#action as span name
        },
        "OpenTelemetry::Instrumentation::PG" => {
          db_statement: :obfuscate,
          peer_service: "postgres"
        },
        "OpenTelemetry::Instrumentation::Redis" => {
          db_statement: :obfuscate,
          peer_service: "redis"
        },
        "OpenTelemetry::Instrumentation::Sidekiq" => {
          propagation_style: :child,
          span_naming: :job_class
        }
      }
      defaults.merge(config.instrumentations)
    end

    private_class_method :configure_traces, :configure_metrics,
                         :build_resource_attributes, :build_instrumentation_config
  end
end
