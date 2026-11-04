require 'rails_helper'

# GHSA-8474-xrp6-wh69: the LoadError check matches the requested name as a literal, never as a
# pattern compiled from it.
RSpec.describe ActiveSupportSafeConstantizeLiteralMatch do
  def safe_constantize_raising(error, name)
    allow(ActiveSupport::Inflector).to receive(:constantize).and_raise(error)
    ActiveSupport::Inflector.safe_constantize(name)
  end

  it 'does not treat regular expression syntax in the requested name as a pattern' do
    error = LoadError.new('Unable to autoload constant ExampleXChannel')

    expect { safe_constantize_raising(error, 'Example.Channel') }.to raise_error(LoadError)
    expect { safe_constantize_raising(error, 'Example.Channel::Nested') }.to raise_error(LoadError)
  end

  it 'returns nil when the error names the first segment of the requested constant' do
    error = LoadError.new('Unable to autoload constant Example.Channel')

    expect(safe_constantize_raising(error, 'Example.Channel::Nested')).to be_nil
  end

  it 'keeps resolving real constants and returning nil for unknown ones' do
    expect('RoomChannel'.safe_constantize).to eq(RoomChannel)
    expect('NoSuchChannelAnywhere'.safe_constantize).to be_nil
  end
end
