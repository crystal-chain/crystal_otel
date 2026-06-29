# frozen_string_literal: true

module CrystalOtel
  module Middleware
    class RequestMetrics
      def initialize(app)
        @app = app
        @meter = OpenTelemetry.meter_provider.meter('crystal_otel.request_metrics')
        @request_duration = @meter.create_histogram(
          'http.server.request.duration',
          unit: 'ms',
          description: 'HTTP server request duration'
        )
        @active_requests = @meter.create_up_down_counter(
          'http.server.active_requests',
          unit: '{request}',
          description: 'Number of active HTTP server requests'
        )
      end

      def call(env)
        attributes = request_attributes(env)
        @active_requests.add(1, attributes: attributes)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)

        status, headers, body = @app.call(env)

        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - start_time
        @request_duration.record(duration, attributes: attributes.merge('http.response.status_code' => status.to_s))
        @active_requests.add(-1, attributes: attributes)

        [status, headers, body]
      rescue StandardError
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - start_time
        @request_duration.record(duration, attributes: attributes.merge('http.response.status_code' => '500'))
        @active_requests.add(-1, attributes: attributes)
        raise
      end

      private

      def request_attributes(env)
        {
          'http.request.method' => env['REQUEST_METHOD'],
          'http.route' => env['PATH_INFO']
        }
      end
    end
  end
end
