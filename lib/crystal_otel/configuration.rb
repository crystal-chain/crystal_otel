# frozen_string_literal: true

module CrystalOtel
  class Configuration
    attr_accessor :service_name, :service_version, :otlp_endpoint, :otlp_protocol,
                  :enabled, :log_correlation, :exception_tracking, :metrics_enabled,
                  :sidekiq_tracing, :neo4j_tracing, :resource_attributes, :instrumentations, :propagators,
                  :sampling_ratio,
                  :batch_max_queue_size, :batch_schedule_delay_ms, :batch_max_export_batch_size

    attr_reader :gauge_definitions, :counter_definitions

    def initialize
      @service_name    = nil
      @service_version = ENV.fetch("APP_VERSION", nil)
      @otlp_endpoint   = ENV.fetch("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")
      @otlp_protocol   = :http
      @enabled         = nil

      @log_correlation    = true
      @exception_tracking = true
      @metrics_enabled    = true
      @sidekiq_tracing    = true
      # Neo4j query tracing. Default on; the installer is a no-op unless
      # neo4j-ruby-driver is loaded, so this is safe for services without Neo4j.
      @neo4j_tracing      = true

      # Seed from the standard OTEL_RESOURCE_ATTRIBUTES env var; app config merges on top.
      @resource_attributes = parse_otel_resource_attributes_env
      @instrumentations    = {}
      @propagators         = %i[tracecontext baggage]

      # Sampling: 1.0 = always sample (default). Values < 1.0 activate
      # parent-based ratio sampling. Reads OTEL_TRACES_SAMPLER_ARG first.
      @sampling_ratio = ENV.fetch("OTEL_TRACES_SAMPLER_ARG", "1.0").to_f.clamp(0.0, 1.0)

      # Batch span processor tuning — mirrors the standard OTEL_BSP_* env vars.
      @batch_max_queue_size       = ENV.fetch("OTEL_BSP_MAX_QUEUE_SIZE", "2048").to_i
      @batch_schedule_delay_ms    = ENV.fetch("OTEL_BSP_SCHEDULE_DELAY", "5000").to_i
      @batch_max_export_batch_size = ENV.fetch("OTEL_BSP_MAX_EXPORT_BATCH_SIZE", "512").to_i

      @gauge_definitions   = []
      @counter_definitions = []
    end

    # Returns true when telemetry should be active.
    #
    # Priority (highest first):
    # 1. CRYSTAL_OTEL_DISABLED=true  — hard kill-switch, overrides everything.
    # 2. config.enabled = false/true — explicit application opt-out/in.
    # 3. Rails.env                  — disabled in test, enabled elsewhere.
    # 4. Non-Rails contexts         — always enabled.
    def enabled?
      return false if ENV.fetch("CRYSTAL_OTEL_DISABLED", nil) == "true"

      if @enabled.nil?
        defined?(Rails) ? !Rails.env.test? : true
      else
        @enabled
      end
    end

    def resolved_service_name
      @service_name || (defined?(Rails) ? Rails.application.class.module_parent_name.underscore : "unknown")
    end

    def business_metrics
      yield BusinessMetricsDsl.new(self)
    end

    def add_gauge(name, description:, callback:)
      @gauge_definitions << { name: name, description: description, callback: callback }
    end

    def add_counter(name, description:, event:)
      @counter_definitions << { name: name, description: description, event: event }
    end

    private

    # Parses the standard OTEL_RESOURCE_ATTRIBUTES env var (key=value,key2=value2).
    # Returns an empty hash when the var is absent or empty.
    def parse_otel_resource_attributes_env
      raw = ENV.fetch("OTEL_RESOURCE_ATTRIBUTES", "")
      return {} if raw.empty?

      raw.split(",").each_with_object({}) do |pair, h|
        k, v = pair.split("=", 2)
        h[k.strip] = v.to_s.strip unless k.nil? || k.strip.empty?
      end
    end
  end

  class BusinessMetricsDsl
    def initialize(config)
      @config = config
    end

    def gauge(name, description:, callback:)
      @config.add_gauge(name, description: description, callback: callback)
    end

    def counter(name, description:, event:)
      @config.add_counter(name, description: description, event: event)
    end
  end
end
