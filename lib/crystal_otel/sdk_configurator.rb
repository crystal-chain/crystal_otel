# frozen_string_literal: true

require "opentelemetry/sdk"
require "opentelemetry-exporter-otlp"

module CrystalOtel
  module SdkConfigurator
    module_function

    def setup!
      config = CrystalOtel.configuration
      return unless config.enabled?

      configure_traces(config)
      configure_metrics(config) if config.metrics_enabled
    end

    def configure_traces(config)
      apply_sampling_env_vars(config)

      OpenTelemetry::SDK.configure do |c|
        c.service_name    = config.resolved_service_name
        c.service_version = config.service_version if config.service_version

        c.resource = OpenTelemetry::SDK::Resources::Resource.create(
          build_resource_attributes(config)
        )

        c.add_span_processor(
          OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
            OpenTelemetry::Exporter::OTLP::Exporter.new(
              endpoint: "#{config.otlp_endpoint}/v1/traces"
            ),
            max_queue_size:        config.batch_max_queue_size,
            schedule_delay:        config.batch_schedule_delay_ms,
            max_export_batch_size: config.batch_max_export_batch_size
          )
        )

        c.use_all(build_instrumentation_config(config))
      end
    end

    def configure_metrics(config)
      require "opentelemetry-metrics-sdk"
      require "opentelemetry-exporter-otlp-metrics"

      metric_exporter = OpenTelemetry::Exporter::OTLP::Metrics::MetricsExporter.new(
        endpoint: "#{config.otlp_endpoint}/v1/metrics"
      )

      metric_reader = OpenTelemetry::SDK::Metrics::Export::PeriodicMetricReader.new(
        exporter: metric_exporter,
        export_interval_millis: 60_000,
        export_timeout_millis:  30_000
      )

      resource = OpenTelemetry::SDK::Resources::Resource.create(
        build_resource_attributes(config)
      )
      OpenTelemetry.meter_provider = OpenTelemetry::SDK::Metrics::MeterProvider.new(resource: resource)
      OpenTelemetry.meter_provider.add_metric_reader(metric_reader)
    end

    def build_resource_attributes(config)
      attrs = {
        "service.name"           => config.resolved_service_name,
        "service.version"        => config.service_version,
        "deployment.environment" => (defined?(Rails) ? Rails.env.to_s : "unknown")
      }
      # config.resource_attributes already includes OTEL_RESOURCE_ATTRIBUTES values;
      # app-level keys win on conflict.
      attrs.merge!(config.resource_attributes)
      attrs.each_with_object({}) { |(k, v), h| h[k] = v.to_s unless v.nil? }
    end

    def build_instrumentation_config(config)
      defaults = {
        "OpenTelemetry::Instrumentation::Rack" => {
          untraced_endpoints: [ "/api/v1/healthz", "/healthz", "/health", "/up" ]
        },
        "OpenTelemetry::Instrumentation::ActionPack" => {
          span_naming: :class
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

    # Sets OTEL_TRACES_SAMPLER / OTEL_TRACES_SAMPLER_ARG env vars when the app
    # configures a ratio < 1.0, but only if the caller hasn't already set them
    # directly. This bridges the gem's sampling_ratio option to the SDK's
    # built-in parent-based ratio sampler without reimplementing sampler logic.
    def apply_sampling_env_vars(config)
      return if config.sampling_ratio >= 1.0
      return if ENV.key?("OTEL_TRACES_SAMPLER")

      ENV["OTEL_TRACES_SAMPLER"]     = "parentbased_traceidratio"
      ENV["OTEL_TRACES_SAMPLER_ARG"] = config.sampling_ratio.to_s
    end

    private_class_method :configure_traces, :configure_metrics,
                         :build_resource_attributes, :build_instrumentation_config,
                         :apply_sampling_env_vars
  end
end
