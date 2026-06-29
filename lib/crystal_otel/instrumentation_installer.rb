# frozen_string_literal: true

module CrystalOtel
  module InstrumentationInstaller
    INSTRUMENTATIONS = %w[
      opentelemetry-instrumentation-rails
      opentelemetry-instrumentation-rack
      opentelemetry-instrumentation-action_pack
      opentelemetry-instrumentation-active_record
      opentelemetry-instrumentation-pg
      opentelemetry-instrumentation-redis
      opentelemetry-instrumentation-sidekiq
      opentelemetry-instrumentation-net_http
      opentelemetry-instrumentation-faraday
      opentelemetry-instrumentation-concurrent_ruby
    ].freeze

    module_function

    def install
      INSTRUMENTATIONS.each do |lib|
        require lib
      rescue LoadError => e
        Rails.logger.warn("[CrystalOtel] Could not load #{lib}: #{e.message}") if defined?(Rails)
      end
    end
  end
end
