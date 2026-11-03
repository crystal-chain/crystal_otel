# frozen_string_literal: true

require "rails"
require "action_dispatch"
require "crystal_otel"
require "opentelemetry-metrics-sdk"

# Runs the middleware in front of a real ActionDispatch router, because the
# route template only exists once Rails has routed the request (and Rails 8
# computes it lazily rather than writing it to env). Labelling with the raw
# PATH_INFO made one http.server.request.duration series per trace ID / UUID /
# scanner probe, which blew up metric cardinality.
RSpec.describe CrystalOtel::Middleware::RequestMetrics do
  let(:recorded) { [] }
  let(:histogram) do
    instance_double(OpenTelemetry::Metrics::Instrument::Histogram).tap do |double|
      allow(double).to receive(:record) { |_duration, attributes:| recorded << attributes }
    end
  end
  let(:counter) { instance_double(OpenTelemetry::Metrics::Instrument::UpDownCounter, add: nil) }
  let(:meter) do
    instance_double(OpenTelemetry::Metrics::Meter, create_histogram: histogram, create_up_down_counter: counter)
  end

  let(:routes) do
    ActionDispatch::Routing::RouteSet.new.tap do |set|
      set.draw do
        get "/api/v2/traces/:id", to: ->(_env) { [ 200, {}, [ "ok" ] ] }
        get "/boom", to: ->(_env) { raise "boom" }
      end
    end
  end

  let(:middleware) { described_class.new(routes) }

  before do
    allow(OpenTelemetry).to receive(:meter_provider)
      .and_return(instance_double(OpenTelemetry::Metrics::MeterProvider, meter: meter))
  end

  def request(path)
    middleware.call(Rack::MockRequest.env_for(path))
  end

  def recorded_attributes
    expect(recorded.size).to eq(1)
    recorded.first
  end

  it "labels a routed request with its route template, not the raw path" do
    request("/api/v2/traces/TR_1735208059000_nLBry6AH")

    expect(recorded_attributes).to eq(
      "http.request.method" => "GET",
      "http.route" => "/api/v2/traces/:id",
      "http.response.status_code" => "200"
    )
  end

  it "collapses requests no route matched into a single label" do
    request("/api/.env")

    expect(recorded_attributes).to include("http.route" => "unmatched", "http.response.status_code" => "404")
  end

  it "records a raising request as a 500 under its route template, then re-raises" do
    expect { request("/boom") }.to raise_error(RuntimeError, "boom")

    expect(recorded_attributes).to include("http.route" => "/boom", "http.response.status_code" => "500")
  end

  it "keeps the route off active_requests so the increment and decrement share attributes" do
    request("/api/v2/traces/TR_1")

    expect(counter).to have_received(:add).with(1, attributes: { "http.request.method" => "GET" }).ordered
    expect(counter).to have_received(:add).with(-1, attributes: { "http.request.method" => "GET" }).ordered
  end
end
