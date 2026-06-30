# frozen_string_literal: true

module CrystalOtel
  module ControllerTracking
    extend ActiveSupport::Concern

    included do
      around_action :otel_trace_action
      after_action :otel_record_response
    end

    private

    def otel_trace_action
      span = OpenTelemetry::Trace.current_span
      return yield unless span.context.valid?

      # Tag span with controller#action for easy identification
      span.set_attribute("code.function", "#{self.class.name}##{action_name}")
      span.set_attribute("http.route", "#{self.class.name}##{action_name}")

      # Record request payload (limited size to avoid bloating traces)
      otel_record_request(span)

      yield
    rescue StandardError => e
      span.record_exception(e)
      span.status = OpenTelemetry::Trace::Status.error(e.message.to_s.truncate(256))
      raise
    end

    def otel_record_request(span)
      span.set_attribute("http.request.method", request.method)
      span.set_attribute("http.request.path", request.path)
      span.set_attribute("http.request.query", request.query_string.truncate(512)) if request.query_string.present?
      span.set_attribute("http.request.content_type", request.content_type.to_s) if request.content_type.present?

      if request.content_type&.include?("json") && request.raw_post.present?
        body = request.raw_post.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?").truncate(2048)
        span.set_attribute("http.request.body", body)
      end

      # Record useful request metadata
      span.set_attribute("enduser.id", current_user.id.to_s) if respond_to?(:current_user, true) && current_user
    rescue StandardError
      # Never fail the request due to tracing
    end

    def otel_record_response
      span = OpenTelemetry::Trace.current_span
      return unless span.context.valid?

      span.set_attribute("http.response.status_code", response.status.to_s)
      span.set_attribute("http.response.content_type", response.content_type.to_s) if response.content_type.present?

      if response.content_type&.include?("json") && response.body.present?
        body = response.body.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?").truncate(2048)
        span.set_attribute("http.response.body", body)
      end

      # Mark 4xx and 5xx responses as errors
      span.status = OpenTelemetry::Trace::Status.error("HTTP #{response.status}") if response.status >= 400
    rescue StandardError
      # Never fail the request due to tracing
    end
  end
end
