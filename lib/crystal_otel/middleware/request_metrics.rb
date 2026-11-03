# frozen_string_literal: true

module CrystalOtel
  module Middleware
    class RequestMetrics
      # Label for requests no route matched (404s, scanner probes such as /api/.env),
      # so they share one series instead of one per probed path.
      UNMATCHED_ROUTE = "unmatched"

      def initialize(app)
        @app = app
        @meter = OpenTelemetry.meter_provider.meter("crystal_otel.request_metrics")
        @request_duration = @meter.create_histogram(
          "http.server.request.duration",
          unit: "ms",
          description: "HTTP server request duration"
        )
        @active_requests = @meter.create_up_down_counter(
          "http.server.active_requests",
          unit: "{request}",
          description: "Number of active HTTP server requests"
        )
      end

      # The route is only known once Rails has routed the request, so it is read
      # after @app.call. active_requests is incremented before routing and must be
      # decremented with the same attributes, so it never carries the route.
      def call(env)
        attributes = { "http.request.method" => env["REQUEST_METHOD"] }
        @active_requests.add(1, attributes: attributes)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)

        status, headers, body = @app.call(env)

        record(env, attributes, start_time, status.to_s)
        [ status, headers, body ]
      rescue StandardError
        record(env, attributes, start_time, "500")
        raise
      end

      private

      def record(env, attributes, start_time, status)
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - start_time
        @request_duration.record(
          duration,
          attributes: attributes.merge("http.route" => route(env), "http.response.status_code" => status)
        )
        @active_requests.add(-1, attributes: attributes)
      end

      # The matched route template ("/api/v2/traces/:id"), never the raw path:
      # raw paths made one series per trace ID / UUID. Goes through
      # ActionDispatch::Request because Rails 8 computes the pattern lazily from
      # env["action_dispatch.route"]; Rails 7.1 sets the env key eagerly; Rails 7.0
      # has no route_uri_pattern at all.
      def route(env)
        request = ActionDispatch::Request.new(env)
        pattern = request.route_uri_pattern if request.respond_to?(:route_uri_pattern)
        pattern&.delete_suffix("(.:format)") || UNMATCHED_ROUTE
      end
    end
  end
end
