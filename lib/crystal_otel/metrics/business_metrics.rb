# frozen_string_literal: true

module CrystalOtel
  module Metrics
    # Manages application-defined counters and gauges registered via
    # +CrystalOtel.configure { |c| c.business_metrics { ... } }+.
    #
    # Counters are event-driven: they subscribe to ActiveSupport::Notifications
    # and increment in the same thread that fires the notification.
    #
    # Gauges are polled: a background thread calls each gauge's callback every
    # GAUGE_COLLECTION_INTERVAL seconds and records the returned value.
    module BusinessMetrics
      GAUGE_COLLECTION_INTERVAL = 30 # seconds

      module_function

      # Creates an OTel counter for each registered counter definition and
      # attaches an ActiveSupport::Notifications subscriber that increments it
      # whenever the named event is published.
      #
      # Event payloads may include:
      # - +:value+  — integer amount to add (defaults to 1 if absent)
      # - +:attributes+ — hash of OTel attribute key/value pairs; keys are
      #   coerced to strings so callers may use symbols or strings interchangeably.
      #
      # Called once during +after_initialize+; calling it again would register
      # duplicate subscribers and double-count events.
      def subscribe_counters
        config = CrystalOtel.configuration
        return if config.counter_definitions.empty?

        meter = OpenTelemetry.meter_provider.meter("crystal_otel.business")

        config.counter_definitions.each do |defn|
          counter = meter.create_counter(
            defn[:name],
            description: defn[:description]
          )

          ActiveSupport::Notifications.subscribe(defn[:event]) do |_name, _start, _finish, _id, payload|
            attributes = payload.fetch(:attributes, {}).transform_keys(&:to_s)
            counter.add(payload.fetch(:value, 1), attributes: attributes)
          end
        end
      end

      # Starts the background gauge-collection thread if it is not already running.
      # Guards against double-start on hot-reload or accidental re-invocation by
      # checking whether the existing thread is still alive before spawning a new one.
      #
      # Only called in server/worker processes (Puma, Sidekiq) to avoid opening
      # database connections in rake tasks or console sessions.
      def start_gauge_collection
        config = CrystalOtel.configuration
        return if config.gauge_definitions.empty?
        return if @gauge_thread&.alive?

        register_gauges

        @gauge_thread = Thread.new do
          loop do
            collect_gauges
            sleep GAUGE_COLLECTION_INTERVAL
          rescue StandardError => e
            Rails.logger.error("[CrystalOtel] Gauge collection error: #{e.message}") if defined?(Rails)
            sleep GAUGE_COLLECTION_INTERVAL
          end
        end
        @gauge_thread.name = "crystal_otel.gauge_collection"
      end

      # Instantiates OTel gauge instruments for every gauge definition and stores
      # them in the module-level +@gauges+ hash, keyed by metric name.
      # Called once before the collection loop starts; gauge objects are reused
      # across every collection cycle rather than recreated on each tick.
      def register_gauges
        @gauges = {}
        meter = OpenTelemetry.meter_provider.meter("crystal_otel.business")

        CrystalOtel.configuration.gauge_definitions.each do |defn|
          @gauges[defn[:name]] = meter.create_gauge(defn[:name], description: defn[:description])
        end
      end

      # Executes each gauge callback and records the result against its instrument.
      #
      # Callback return values are handled as follows:
      # - Hash  — treated as a breakdown by category. Each key becomes a "category"
      #   attribute; Array keys are joined with "." (e.g. ActiveRecord +group+
      #   results with multiple columns).
      # - Scalar — recorded as a single integer with no attributes.
      #
      # Errors from individual callbacks are caught and logged so that one broken
      # gauge cannot interrupt collection of the remaining gauges.
      def collect_gauges
        config = CrystalOtel.configuration
        return if config.gauge_definitions.empty? || @gauges.nil?

        config.gauge_definitions.each do |defn|
          result = defn[:callback].call
          gauge = @gauges[defn[:name]]
          next unless gauge

          case result
          when Hash
            result.each do |key, value|
              attrs = key.is_a?(Array) ? { "category" => key.join(".") } : { "category" => key.to_s }
              gauge.record(value, attributes: attrs)
            end
          else
            gauge.record(result.to_i)
          end
        rescue StandardError => e
          Rails.logger.error("[CrystalOtel] Error collecting gauge #{defn[:name]}: #{e.message}") if defined?(Rails)
        end
      end
    end
  end
end
