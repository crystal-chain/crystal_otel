# frozen_string_literal: true

require_relative 'lib/crystal_otel/version'

Gem::Specification.new do |spec|
  spec.name = 'crystal_otel'
  spec.version = CrystalOtel::VERSION
  spec.authors = ['Crystal Chain']
  spec.summary = 'OpenTelemetry integration for Crystal Chain Rails apps'
  spec.description = 'Reusable OpenTelemetry gem providing tracing, metrics, log correlation, and exception tracking for Rails applications.'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.homepage = 'https://github.com/crystal-chain/crystalchain_otel'
  spec.metadata['source_code_uri']   = spec.homepage
  spec.metadata['changelog_uri']     = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['allowed_push_host'] = 'https://rubygems.pkg.github.com'
  spec.metadata['github_repo']       = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir['lib/**/*', 'LICENSE', 'README.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'rails', '>= 7.0'

  # OpenTelemetry core
  spec.add_dependency 'opentelemetry-exporter-otlp', '~> 0.32'
  spec.add_dependency 'opentelemetry-exporter-otlp-metrics', '~> 0.7'
  spec.add_dependency 'opentelemetry-metrics-sdk', '~> 0.12'
  spec.add_dependency 'opentelemetry-sdk', '~> 1.10'

  # Auto-instrumentation
  spec.add_dependency 'opentelemetry-instrumentation-action_pack', '~> 0.15'
  spec.add_dependency 'opentelemetry-instrumentation-active_record', '~> 0.11'
  spec.add_dependency 'opentelemetry-instrumentation-concurrent_ruby', '~> 0.24'
  spec.add_dependency 'opentelemetry-instrumentation-faraday', '~> 0.31'
  spec.add_dependency 'opentelemetry-instrumentation-net_http', '~> 0.27'
  spec.add_dependency 'opentelemetry-instrumentation-pg', '~> 0.35'
  spec.add_dependency 'opentelemetry-instrumentation-rack', '~> 0.29'
  spec.add_dependency 'opentelemetry-instrumentation-rails', '~> 0.39'
  spec.add_dependency 'opentelemetry-instrumentation-redis', '~> 0.28'
  spec.add_dependency 'opentelemetry-instrumentation-sidekiq', '~> 0.28'
end
