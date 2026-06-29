# frozen_string_literal: true

module CrystalOtel
  module Logging
    class TraceLogFormatter
      def initialize(original_formatter = nil)
        @original_formatter = original_formatter || ::Logger::Formatter.new
      end

      def call(severity, timestamp, progname, msg)
        span_context = OpenTelemetry::Trace.current_span.context

        if span_context.valid?
          trace_id = span_context.hex_trace_id
          span_id = span_context.hex_span_id
          prefix = "[trace_id=#{trace_id} span_id=#{span_id}] "
          msg = "#{prefix}#{msg}"
        end

        @original_formatter.call(severity, timestamp, progname, msg)
      end

      # Delegate TaggedLogging methods to the original formatter
      def tagged(*tags, &)
        @original_formatter.tagged(*tags, &)
      end

      def push_tags(*tags)
        @original_formatter.push_tags(*tags)
      end

      def pop_tags(count = 1)
        @original_formatter.pop_tags(count)
      end

      delegate :clear_tags!, to: :@original_formatter

      delegate :current_tags, to: :@original_formatter

      delegate :tags_text, to: :@original_formatter

      # Forward any other missing methods to the original formatter
      def respond_to_missing?(method, include_private = false)
        @original_formatter.respond_to?(method, include_private) || super
      end

      def method_missing(method, ...)
        if @original_formatter.respond_to?(method)
          @original_formatter.send(method, ...)
        else
          super
        end
      end
    end
  end
end
