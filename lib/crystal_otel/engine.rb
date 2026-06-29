# frozen_string_literal: true

module CrystalOtel
  class Engine < ::Rails::Engine
    isolate_namespace CrystalOtel

    # Wires up the OTel SDK after Rails (and any other engines) have had a chance
    # to call OpenTelemetry::SDK.configure themselves. Running *after*
    # "opentelemetry.configure" prevents a double-configure race where the SDK
    # resets instrumentation already registered by an earlier initializer.
    initializer "crystal_otel.configure_sdk", after: "opentelemetry.configure" do
      next unless CrystalOtel.configuration.enabled?

      InstrumentationInstaller.install
      SdkConfigurator.setup!
    end

    # Wraps the Rails logger formatter so that every log line emits the current
    # OTel trace_id and span_id. Runs after :initialize_logger to ensure
    # Rails.logger is already set before we decorate it.
    initializer "crystal_otel.log_correlation", after: :initialize_logger do
      next unless CrystalOtel.configuration.enabled?
      next unless CrystalOtel.configuration.log_correlation

      if defined?(Rails) && Rails.logger
        original_formatter = Rails.logger.formatter
        Rails.logger.formatter = Logging::TraceLogFormatter.new(original_formatter)
      end
    end

    # Inserts Rack middleware immediately after ActionDispatch::RequestId so that
    # the request ID is available to both middlewares via request headers.
    # - ExceptionTracker: captures unhandled exceptions as OTel span events.
    # - RequestMetrics: records HTTP request duration and status-code counters.
    # Each middleware is only added when the corresponding feature flag is on.
    initializer "crystal_otel.middleware" do |app|
      next unless CrystalOtel.configuration.enabled?

      if CrystalOtel.configuration.exception_tracking
        app.middleware.insert_after ActionDispatch::RequestId,
                                    Middleware::ExceptionTracker
      end
      if CrystalOtel.configuration.metrics_enabled
        app.middleware.insert_after ActionDispatch::RequestId,
                                    Middleware::RequestMetrics
      end
    end

    # Placeholder for Sidekiq-specific setup. The actual auto-instrumentation for
    # Sidekiq is handled by the opentelemetry-instrumentation-sidekiq gem loaded
    # via +use_all+ in SdkConfigurator#configure_traces; no additional code is
    # needed here beyond the guard checks.
    initializer "crystal_otel.sidekiq" do
      next unless CrystalOtel.configuration.enabled?
      next unless CrystalOtel.configuration.sidekiq_tracing
      next unless defined?(Sidekiq)

      # Sidekiq instrumentation is handled via use_all in SdkConfigurator
    end

    # Starts Ruby runtime metrics collection (GC stats, thread counts, memory).
    # Uses two strategies:
    # 1. Subscribes to the "crystalcollect.server.started" notification so it can
    #    start if the application fires that event after initialization.
    # 2. Starts immediately inside after_initialize when running under Puma or
    #    Sidekiq::CLI, covering the common server/worker boot path.
    initializer "crystal_otel.runtime_metrics" do
      next unless CrystalOtel.configuration.enabled?
      next unless CrystalOtel.configuration.metrics_enabled

      ActiveSupport::Notifications.subscribe("crystalcollect.server.started") do
        Metrics::RuntimeMetrics.start
      end

      # Start immediately if we're in a server context (Puma)
      config.after_initialize do
        Metrics::RuntimeMetrics.start if defined?(Puma) || defined?(Sidekiq::CLI)
      end
    end

    # Activates application-defined business metrics after the full Rails app is
    # initialized so that all models and constants referenced in gauge callbacks
    # are available. Counter subscriptions are registered in all process types;
    # gauge collection is limited to long-running server/worker processes to avoid
    # opening persistent DB connections in one-shot processes like rake tasks.
    initializer "crystal_otel.business_metrics" do
      next unless CrystalOtel.configuration.enabled?
      next unless CrystalOtel.configuration.metrics_enabled

      config.after_initialize do
        Metrics::BusinessMetrics.subscribe_counters
        Metrics::BusinessMetrics.start_gauge_collection if defined?(Puma) || defined?(Sidekiq::CLI)
      end
    end
  end
end
