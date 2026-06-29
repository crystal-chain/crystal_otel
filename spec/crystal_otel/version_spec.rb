require 'spec_helper'

RSpec.describe CrystalOtel do
  it 'has a version string' do
    expect(CrystalOtel::VERSION).to be_a(String)
  end

  it 'version follows semver format' do
    expect(CrystalOtel::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
