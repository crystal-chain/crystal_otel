# frozen_string_literal: true

module CrystalOtel
  module Middleware
    class ExceptionTracker
      def initialize(app)
        @app = app
      end

      def call(env)
        status, headers, body = @app.call(env)

        # Mark 4xx and 5xx responses as errors on the span
        if status.to_i >= 400
          span = OpenTelemetry::Trace.current_span
          span.status = OpenTelemetry::Trace::Status.error("HTTP #{status}")
        end

        [status, headers, body]
      rescue Exception => e # rubocop:disable Lint/RescueException
        # Truly unhandled exceptions that crash the request
        span = OpenTelemetry::Trace.current_span
        span.record_exception(e)
        span.status = OpenTelemetry::Trace::Status.error(e.message.to_s[0..255])
        raise
      end
    end
  end
end
