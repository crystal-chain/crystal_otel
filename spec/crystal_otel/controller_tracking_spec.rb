require 'spec_helper'
require 'active_support/concern'
require 'crystal_otel/controller_tracking'

# Minimal host so the ActiveSupport::Concern `included` block (which registers
# around_action/after_action callbacks) succeeds without a real controller.
class FakeOtelController
  def self.around_action(*); end
  def self.after_action(*); end

  include CrystalOtel::ControllerTracking
end

RSpec.describe CrystalOtel::ControllerTracking do
  subject(:controller) { FakeOtelController.new }

  describe '#otel_utf8' do
    it 'replaces an invalid lone byte with "?"' do
      expect(controller.send(:otel_utf8, "\xC3")).to eq('?')
    end

    it 'preserves valid multibyte UTF-8 (é) from ASCII-8BIT bytes' do
      bytes = "\xC3\xA9".dup.force_encoding('ASCII-8BIT')
      result = controller.send(:otel_utf8, bytes)

      expect(result).to eq('é')
      expect(result.valid_encoding?).to be(true)
      expect(result.encoding).to eq(Encoding::UTF_8)
    end

    it 'scrubs invalid bytes embedded in otherwise valid text' do
      result = controller.send(:otel_utf8, "ok\xC3bad")

      expect(result).to eq('ok?bad')
      expect(result.valid_encoding?).to be(true)
    end

    it 'leaves a body already tagged UTF-8 with invalid bytes valid (the encode no-op case)' do
      body = "\xC3".dup.force_encoding('UTF-8')
      result = controller.send(:otel_utf8, body)

      expect(result.valid_encoding?).to be(true)
      expect(result).to eq('?')
    end

    it 'does not mutate the original argument' do
      original = "\xC3".dup.force_encoding('UTF-8')
      controller.send(:otel_utf8, original)

      expect(original.bytes).to eq([ 0xC3 ])
    end

    it 'coerces non-string input via to_s' do
      expect(controller.send(:otel_utf8, nil)).to eq('')
      expect(controller.send(:otel_utf8, 123)).to eq('123')
    end
  end
end
