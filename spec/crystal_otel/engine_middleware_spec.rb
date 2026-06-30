# frozen_string_literal: true

require "rails"
require "action_dispatch"
require "crystal_otel"

# Integration spec for the engine's middleware wiring. Unhandled controller
# exceptions are caught and rendered by ActionDispatch::ShowExceptions /
# DebugExceptions, which never re-raise. So the ExceptionTracker can only call
# span.record_exception if it is positioned *inside* (below) those middlewares
# in the stack. If it sits outside them, the exception is already swallowed by
# the time it would propagate up, and nothing is ever recorded.
RSpec.describe CrystalOtel::Engine do
  describe "exception tracker middleware position" do
    # A slice of the real Rails default middleware stack, in Rails' own order:
    # RequestId is outermost; ShowExceptions/DebugExceptions sit further in and
    # turn raised exceptions into HTTP error responses.
    def build_stack
      stack = ActionDispatch::MiddlewareStack.new
      stack.use ActionDispatch::RequestId
      stack.use ActionDispatch::ShowExceptions
      stack.use ActionDispatch::DebugExceptions
      stack
    end

    let(:fake_app) { Struct.new(:middleware).new(build_stack) }

    def run_middleware_initializer(app)
      initializer = CrystalOtel::Engine.initializers.find { |i| i.name == "crystal_otel.middleware" }
      initializer.run(app)
    end

    before do
      CrystalOtel.configure do |c|
        c.enabled            = true
        c.exception_tracking = true
        c.metrics_enabled    = false
      end
    end

    it "inserts ExceptionTracker inside DebugExceptions so raised exceptions reach it" do
      run_middleware_initializer(fake_app)

      mws = fake_app.middleware.middlewares
      tracker_index = mws.index { |m| m.klass == CrystalOtel::Middleware::ExceptionTracker }
      debug_index   = mws.index { |m| m.klass == ActionDispatch::DebugExceptions }

      expect(tracker_index).not_to be_nil
      expect(tracker_index).to be > debug_index
    end
  end
end
