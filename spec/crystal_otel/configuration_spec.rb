# frozen_string_literal: true

require "spec_helper"

RSpec.describe CrystalOtel::Configuration do
  subject(:config) { described_class.new }

  # Restore env vars touched by individual examples
  around do |example|
    saved = %w[
      OTEL_EXPORTER_OTLP_ENDPOINT APP_VERSION CRYSTAL_OTEL_DISABLED
      OTEL_TRACES_SAMPLER_ARG OTEL_RESOURCE_ATTRIBUTES
      OTEL_BSP_MAX_QUEUE_SIZE OTEL_BSP_SCHEDULE_DELAY OTEL_BSP_MAX_EXPORT_BATCH_SIZE
    ].each_with_object({}) { |k, h| h[k] = ENV.fetch(k, nil) }

    example.run
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV.store(k, v) }
  end

  describe "defaults" do
    it "has nil service_name (resolved at runtime)" do
      expect(config.service_name).to be_nil
    end

    it "defaults otlp_endpoint to localhost:4318" do
      expect(config.otlp_endpoint).to eq("http://localhost:4318")
    end

    it "defaults otlp_protocol to :http" do
      expect(config.otlp_protocol).to eq(:http)
    end

    it "defaults log_correlation to true" do
      expect(config.log_correlation).to be true
    end

    it "defaults exception_tracking to true" do
      expect(config.exception_tracking).to be true
    end

    it "defaults metrics_enabled to true" do
      expect(config.metrics_enabled).to be true
    end

    it "defaults sidekiq_tracing to true" do
      expect(config.sidekiq_tracing).to be true
    end

    it "defaults resource_attributes to empty hash when env var absent" do
      ENV.delete("OTEL_RESOURCE_ATTRIBUTES")
      expect(described_class.new.resource_attributes).to eq({})
    end

    it "defaults propagators to tracecontext and baggage" do
      expect(config.propagators).to eq(%i[tracecontext baggage])
    end

    it "defaults sampling_ratio to 1.0 (always sample)" do
      ENV.delete("OTEL_TRACES_SAMPLER_ARG")
      expect(described_class.new.sampling_ratio).to eq(1.0)
    end

    it "defaults batch_max_queue_size to 2048" do
      ENV.delete("OTEL_BSP_MAX_QUEUE_SIZE")
      expect(described_class.new.batch_max_queue_size).to eq(2048)
    end

    it "defaults batch_schedule_delay_ms to 5000" do
      ENV.delete("OTEL_BSP_SCHEDULE_DELAY")
      expect(described_class.new.batch_schedule_delay_ms).to eq(5000)
    end

    it "defaults batch_max_export_batch_size to 512" do
      ENV.delete("OTEL_BSP_MAX_EXPORT_BATCH_SIZE")
      expect(described_class.new.batch_max_export_batch_size).to eq(512)
    end

    it "starts with empty gauge definitions" do
      expect(config.gauge_definitions).to be_empty
    end

    it "starts with empty counter definitions" do
      expect(config.counter_definitions).to be_empty
    end
  end

  describe "#enabled?" do
    context "when CRYSTAL_OTEL_DISABLED=true" do
      before { ENV["CRYSTAL_OTEL_DISABLED"] = "true" }

      it "returns false regardless of @enabled or Rails env" do
        config.enabled = true
        expect(config.enabled?).to be false
      end
    end

    context "when CRYSTAL_OTEL_DISABLED is absent" do
      before { ENV.delete("CRYSTAL_OTEL_DISABLED") }

      it "returns false in Rails test environment when @enabled is not set" do
        expect(config.enabled?).to be false
      end

      it "returns false when explicitly set to false" do
        config.enabled = false
        expect(config.enabled?).to be false
      end

      it "returns true when explicitly set to true" do
        config.enabled = true
        expect(config.enabled?).to be true
      end
    end
  end

  describe "env-var overrides" do
    it "reads otlp_endpoint from OTEL_EXPORTER_OTLP_ENDPOINT" do
      ENV["OTEL_EXPORTER_OTLP_ENDPOINT"] = "https://otel.example.com"
      expect(described_class.new.otlp_endpoint).to eq("https://otel.example.com")
    end

    it "reads service_version from APP_VERSION" do
      ENV["APP_VERSION"] = "abc1234"
      expect(described_class.new.service_version).to eq("abc1234")
    end

    it "defaults service_version to nil when APP_VERSION is absent" do
      ENV.delete("APP_VERSION")
      expect(described_class.new.service_version).to be_nil
    end

    it "reads sampling_ratio from OTEL_TRACES_SAMPLER_ARG" do
      ENV["OTEL_TRACES_SAMPLER_ARG"] = "0.25"
      expect(described_class.new.sampling_ratio).to eq(0.25)
    end

    it "clamps sampling_ratio to [0.0, 1.0]" do
      ENV["OTEL_TRACES_SAMPLER_ARG"] = "2.5"
      expect(described_class.new.sampling_ratio).to eq(1.0)
    end

    it "reads batch_max_queue_size from OTEL_BSP_MAX_QUEUE_SIZE" do
      ENV["OTEL_BSP_MAX_QUEUE_SIZE"] = "4096"
      expect(described_class.new.batch_max_queue_size).to eq(4096)
    end

    it "reads batch_schedule_delay_ms from OTEL_BSP_SCHEDULE_DELAY" do
      ENV["OTEL_BSP_SCHEDULE_DELAY"] = "1000"
      expect(described_class.new.batch_schedule_delay_ms).to eq(1000)
    end

    it "reads batch_max_export_batch_size from OTEL_BSP_MAX_EXPORT_BATCH_SIZE" do
      ENV["OTEL_BSP_MAX_EXPORT_BATCH_SIZE"] = "256"
      expect(described_class.new.batch_max_export_batch_size).to eq(256)
    end
  end

  describe "OTEL_RESOURCE_ATTRIBUTES parsing" do
    it "parses key=value pairs into resource_attributes" do
      ENV["OTEL_RESOURCE_ATTRIBUTES"] = "service.namespace=crystalcollect,team=platform"
      attrs = described_class.new.resource_attributes
      expect(attrs["service.namespace"]).to eq("crystalcollect")
      expect(attrs["team"]).to eq("platform")
    end

    it "handles a single attribute" do
      ENV["OTEL_RESOURCE_ATTRIBUTES"] = "deployment.environment=production"
      expect(described_class.new.resource_attributes["deployment.environment"]).to eq("production")
    end

    it "returns empty hash when env var is blank" do
      ENV["OTEL_RESOURCE_ATTRIBUTES"] = ""
      expect(described_class.new.resource_attributes).to eq({})
    end

    it "app config merge overrides env var values" do
      ENV["OTEL_RESOURCE_ATTRIBUTES"] = "service.namespace=from-env"
      cfg = described_class.new
      cfg.resource_attributes["service.namespace"] = "from-app"
      expect(cfg.resource_attributes["service.namespace"]).to eq("from-app")
    end
  end

  describe "#business_metrics DSL" do
    it "registers a gauge via the block DSL" do
      config.business_metrics do |m|
        m.gauge "my.gauge", description: "A gauge", callback: -> { 42 }
      end

      defn = config.gauge_definitions.first
      expect(defn[:name]).to eq("my.gauge")
      expect(defn[:callback].call).to eq(42)
    end

    it "registers a counter via the block DSL" do
      config.business_metrics do |m|
        m.counter "my.counter", description: "A counter", event: "my.event"
      end

      defn = config.counter_definitions.first
      expect(defn[:name]).to eq("my.counter")
      expect(defn[:event]).to eq("my.event")
    end

    it "accumulates multiple metrics across calls" do
      config.business_metrics { |m| m.gauge "g1", description: "G1", callback: -> { 1 } }
      config.business_metrics { |m| m.gauge "g2", description: "G2", callback: -> { 2 } }

      expect(config.gauge_definitions.map { |d| d[:name] }).to eq(%w[g1 g2])
    end
  end

  describe "CrystalOtel module interface" do
    it "exposes a configuration singleton" do
      expect(CrystalOtel.configuration).to be_a(described_class)
    end

    it "returns the same instance on repeated calls" do
      expect(CrystalOtel.configuration).to be(CrystalOtel.configuration)
    end

    it "yields configuration in a configure block" do
      CrystalOtel.configure { |c| c.service_name = "test-service" }
      expect(CrystalOtel.configuration.service_name).to eq("test-service")
    end

    it "resets to a fresh configuration with reset!" do
      CrystalOtel.configure { |c| c.service_name = "old" }
      CrystalOtel.reset!
      expect(CrystalOtel.configuration.service_name).to be_nil
    end
  end
end
