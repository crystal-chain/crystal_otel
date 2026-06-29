# frozen_string_literal: true

module CrystalOtel
  class Configuration
    attr_accessor :service_name, :service_version, :otlp_endpoint, :otlp_protocol,
                  :enabled, :log_correlation, :exception_tracking, :metrics_enabled,
                  :sidekiq_tracing, :resource_attributes, :instrumentations, :propagators

    attr_reader :gauge_definitions, :counter_definitions

    def initialize
      @service_name = nil # Falls back to Rails app name via resolved_service_name
      @service_version = ENV.fetch('APP_VERSION', nil)
      @otlp_endpoint = ENV.fetch('OTEL_EXPORTER_OTLP_ENDPOINT', 'http://localhost:4318')
      @otlp_protocol = :http
      @enabled = nil # Resolved lazily; see enabled?
      @log_correlation = true
      @exception_tracking = true
      @metrics_enabled = true
      @sidekiq_tracing = true
      @resource_attributes = {}
      @instrumentations = {}
      @propagators = %i[tracecontext baggage]
      @gauge_definitions = []
      @counter_definitions = []
    end

    # Returns true when telemetry should be active. Lazy resolution allows the
    # enabled state to depend on the Rails environment without requiring it to
    # be set before Rails boots.
    #
    # When @enabled has not been set explicitly:
    # - Rails apps: disabled in the test environment, enabled otherwise.
    # - Non-Rails contexts: always enabled.
    #
    # Set config.enabled = false to disable unconditionally in any environment.
    def enabled?
      if @enabled.nil?
        defined?(Rails) ? !Rails.env.test? : true
      else
        @enabled
      end
    end

    # Returns the service name used in all OTel signals.
    # Falls back to the Rails application module name (underscored) when
    # +service_name+ has not been set explicitly, so a minimal setup still
    # produces a meaningful name in dashboards without any configuration.
    # Falls back further to "unknown" when Rails is not defined.
    def resolved_service_name
      @service_name || (defined?(Rails) ? Rails.application.class.module_parent_name.underscore : 'unknown')
    end

    # Yields a BusinessMetricsDsl instance to allow a clean block-based syntax
    # for registering gauges and counters:
    #
    #   config.business_metrics do |m|
    #     m.gauge   "my.gauge",   description: "...", callback: -> { Model.count }
    #     m.counter "my.counter", description: "...", event: "my.event"
    #   end
    def business_metrics
      yield BusinessMetricsDsl.new(self)
    end

    def add_gauge(name, description:, callback:)
      @gauge_definitions << { name: name, description: description, callback: callback }
    end

    def add_counter(name, description:, event:)
      @counter_definitions << { name: name, description: description, event: event }
    end
  end

  # Thin DSL wrapper yielded by Configuration#business_metrics.
  # Delegates gauge/counter registration to the underlying Configuration object
  # while exposing a cleaner method-based API inside the block.
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
