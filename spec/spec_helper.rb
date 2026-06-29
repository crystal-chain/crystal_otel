require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
end

# Stub Rails-dependent constants so the plain-Ruby layer loads without a full
# Rails boot. Tests that exercise Rails-specific behaviour should load Rails
# themselves and are kept in a separate integration suite.
module Rails
  def self.env
    ActiveSupport::StringInquirer.new('test')
  end

  def self.logger
    nil
  end

  def self.application
    nil
  end
end

module ActiveSupport
  class StringInquirer < String
    def method_missing(method, *args)
      method.to_s.end_with?('?') ? self == method.to_s.chomp('?') : super
    end

    def respond_to_missing?(method, include_private = false)
      method.to_s.end_with?('?') || super
    end
  end
end

require 'crystal_otel/version'
require 'crystal_otel/configuration'

# Define the CrystalOtel module-level interface without loading the full gem
# (which would pull in OpenTelemetry SDK and instrumentation gems that are not
# needed for these plain-Ruby unit tests).
module CrystalOtel
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset!
      @configuration = Configuration.new
    end
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.order = :random
  Kernel.srand config.seed

  config.after do
    CrystalOtel.reset!
  end
end
