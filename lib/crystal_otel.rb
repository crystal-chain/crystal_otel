# frozen_string_literal: true

require "crystal_otel/version"
require "crystal_otel/configuration"

module CrystalOtel
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset!
      @configuration = Configuration.new
    end

    def trace(name, attributes: {})
      return yield unless defined?(OpenTelemetry) && configuration.enabled?

      OpenTelemetry.tracer_provider.tracer("crystal_otel.app")
                   .in_span(name, attributes: attributes) { |span| yield(span) }
    end
  end
end

require "crystal_otel/sdk_configurator"
require "crystal_otel/instrumentation_installer"
require "crystal_otel/logging/trace_log_formatter"
require "crystal_otel/middleware/exception_tracker"
require "crystal_otel/middleware/request_metrics"
require "crystal_otel/metrics/runtime_metrics"
require "crystal_otel/metrics/business_metrics"
require "crystal_otel/controller_tracking"
require "crystal_otel/instrumentation/neo4j"
require "crystal_otel/engine" if defined?(Rails::Engine)
