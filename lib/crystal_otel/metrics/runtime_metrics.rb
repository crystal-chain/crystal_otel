# frozen_string_literal: true

module CrystalOtel
  module Metrics
    module RuntimeMetrics
      COLLECTION_INTERVAL = 15 # seconds

      module_function

      def start
        return if @running

        @running = true
        meter = OpenTelemetry.meter_provider.meter("crystal_otel.runtime")

        meter.create_observable_gauge(
          "process.runtime.ruby.gc.count",
          callback: -> { GC.count },
          description: "Ruby GC run count"
        )

        meter.create_observable_gauge(
          "process.runtime.ruby.thread.count",
          callback: -> { Thread.list.count },
          description: "Ruby thread count"
        )

        meter.create_observable_gauge(
          "process.runtime.ruby.memory.rss",
          callback: -> { rss_bytes },
          unit: "By",
          description: "Ruby process RSS memory in bytes"
        )

        Rails.logger.info("[CrystalOtel] Runtime metrics collection started") if defined?(Rails)
      end

      def stop
        @running = false
      end

      def rss_bytes
        if RUBY_PLATFORM.include?("linux")
          File.read("/proc/self/statm").split[1].to_i * 4096
        elsif RUBY_PLATFORM.include?("darwin")
          `ps -o rss= -p #{Process.pid}`.strip.to_i * 1024
        else
          0
        end
      rescue StandardError
        0
      end

      private_class_method :rss_bytes
    end
  end
end
