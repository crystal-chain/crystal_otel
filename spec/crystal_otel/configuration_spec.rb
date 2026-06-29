require 'spec_helper'

RSpec.describe CrystalOtel::Configuration do
  subject(:config) { described_class.new }

  describe 'defaults' do
    it 'has nil service_name (resolved at runtime)' do
      expect(config.service_name).to be_nil
    end

    it 'defaults otlp_endpoint to localhost:4318' do
      expect(config.otlp_endpoint).to eq('http://localhost:4318')
    end

    it 'defaults otlp_protocol to :http' do
      expect(config.otlp_protocol).to eq(:http)
    end

    it 'defaults log_correlation to true' do
      expect(config.log_correlation).to be true
    end

    it 'defaults exception_tracking to true' do
      expect(config.exception_tracking).to be true
    end

    it 'defaults metrics_enabled to true' do
      expect(config.metrics_enabled).to be true
    end

    it 'defaults sidekiq_tracing to true' do
      expect(config.sidekiq_tracing).to be true
    end

    it 'defaults resource_attributes to empty hash' do
      expect(config.resource_attributes).to eq({})
    end

    it 'defaults propagators to tracecontext and baggage' do
      expect(config.propagators).to eq(%i[tracecontext baggage])
    end

    it 'starts with empty gauge definitions' do
      expect(config.gauge_definitions).to be_empty
    end

    it 'starts with empty counter definitions' do
      expect(config.counter_definitions).to be_empty
    end
  end

  describe '#enabled?' do
    context 'when @enabled is not set' do
      it 'returns false in Rails test environment' do
        # Rails.env is stubbed to return 'test' in spec_helper
        expect(config.enabled?).to be false
      end
    end

    context 'when explicitly set to false' do
      before { config.enabled = false }

      it 'returns false regardless of Rails environment' do
        expect(config.enabled?).to be false
      end
    end

    context 'when explicitly set to true' do
      before { config.enabled = true }

      it 'returns true regardless of Rails environment' do
        expect(config.enabled?).to be true
      end
    end
  end

  describe 'env-var overrides' do
    around do |example|
      saved_endpoint = ENV.fetch('OTEL_EXPORTER_OTLP_ENDPOINT', nil)
      saved_version  = ENV.fetch('APP_VERSION', nil)
      example.run
    ensure
      ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] = saved_endpoint
      ENV['APP_VERSION']                  = saved_version
    end

    it 'reads otlp_endpoint from OTEL_EXPORTER_OTLP_ENDPOINT' do
      ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] = 'https://otel.example.com'
      cfg = described_class.new
      expect(cfg.otlp_endpoint).to eq('https://otel.example.com')
    end

    it 'reads service_version from APP_VERSION' do
      ENV['APP_VERSION'] = 'abc1234'
      cfg = described_class.new
      expect(cfg.service_version).to eq('abc1234')
    end

    it 'defaults service_version to nil when APP_VERSION is absent' do
      ENV.delete('APP_VERSION')
      expect(described_class.new.service_version).to be_nil
    end
  end

  describe '#business_metrics DSL' do
    it 'registers a gauge via the block DSL' do
      config.business_metrics do |m|
        m.gauge 'my.gauge', description: 'A gauge', callback: -> { 42 }
      end

      expect(config.gauge_definitions.length).to eq(1)
      defn = config.gauge_definitions.first
      expect(defn[:name]).to eq('my.gauge')
      expect(defn[:description]).to eq('A gauge')
      expect(defn[:callback].call).to eq(42)
    end

    it 'registers a counter via the block DSL' do
      config.business_metrics do |m|
        m.counter 'my.counter', description: 'A counter', event: 'my.event'
      end

      expect(config.counter_definitions.length).to eq(1)
      defn = config.counter_definitions.first
      expect(defn[:name]).to eq('my.counter')
      expect(defn[:description]).to eq('A counter')
      expect(defn[:event]).to eq('my.event')
    end

    it 'accumulates multiple metrics across calls' do
      config.business_metrics do |m|
        m.gauge   'g1', description: 'Gauge 1',   callback: -> { 1 }
        m.counter 'c1', description: 'Counter 1', event: 'ev1'
      end

      config.business_metrics do |m|
        m.gauge 'g2', description: 'Gauge 2', callback: -> { 2 }
      end

      expect(config.gauge_definitions.map { |d| d[:name] }).to eq(%w[g1 g2])
      expect(config.counter_definitions.map { |d| d[:name] }).to eq(%w[c1])
    end
  end

  describe 'CrystalOtel module interface' do
    it 'exposes a configuration singleton' do
      expect(CrystalOtel.configuration).to be_a(described_class)
    end

    it 'returns the same instance on repeated calls' do
      expect(CrystalOtel.configuration).to be(CrystalOtel.configuration)
    end

    it 'yields configuration in a configure block' do
      CrystalOtel.configure do |c|
        c.service_name = 'test-service'
      end

      expect(CrystalOtel.configuration.service_name).to eq('test-service')
    end

    it 'resets to a fresh configuration with reset!' do
      CrystalOtel.configure { |c| c.service_name = 'old' }
      CrystalOtel.reset!
      expect(CrystalOtel.configuration.service_name).to be_nil
    end
  end
end
