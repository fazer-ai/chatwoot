require 'rails_helper'

# Every lenient reading of one of these fails in the expensive direction, so the words are
# listed rather than inferred.
describe Import::Options do
  after { %w[FLAG COUNT MEASURE].each { |key| ENV.delete(key) } }

  describe '.boolean' do
    it 'takes the default when nothing was set' do
      expect(described_class.boolean('FLAG')).to be(false)
      expect(described_class.boolean('FLAG', default: true)).to be(true)
    end

    %w[1 true YES on sim].each do |word|
      it "reads #{word} as true" do
        ENV['FLAG'] = word
        expect(described_class.boolean('FLAG')).to be(true)
      end
    end

    # `ActiveModel::Type::Boolean` answers every one of these with true, because none is in
    # its own false list. Under that reading `ATTACHMENTS=no` mirrors hundreds of gigabytes.
    %w[0 false NO off nao].each do |word|
      it "reads #{word} as false, where the Rails caster reads it as true" do
        ENV['FLAG'] = word
        expect(described_class.boolean('FLAG')).to be(false)
        expect(ActiveModel::Type::Boolean.new.cast(word).present?).to be(true) if %w[no nao].include?(word.downcase)
      end
    end

    it 'refuses a word it cannot read rather than guessing which way it went' do
      ENV['FLAG'] = 'flase'
      expect { described_class.boolean('FLAG') }.to raise_error(ArgumentError, /FLAG/)
    end
  end

  describe '.integer' do
    it 'takes a count' do
      ENV['COUNT'] = '400'
      expect(described_class.integer('COUNT')).to eq(400)
    end

    # `SAMPLE=0.5` truncates to zero at the call site and the scan classifies nothing while
    # printing a finished projection.
    it 'refuses a fraction rather than truncating it' do
      ENV['COUNT'] = '0.5'
      expect { described_class.integer('COUNT') }.to raise_error(ArgumentError, /COUNT/)
    end

    it 'refuses zero, which every setting that takes one reads as an instruction' do
      ENV['COUNT'] = '0'
      expect { described_class.integer('COUNT') }.to raise_error(ArgumentError, /COUNT/)
    end

    it 'refuses a word' do
      ENV['COUNT'] = 'muito'
      expect { described_class.integer('COUNT') }.to raise_error(ArgumentError, /COUNT/)
    end
  end

  describe '.decimal' do
    it 'takes a fraction, since a load average is one' do
      ENV['MEASURE'] = '2.5'
      expect(described_class.decimal('MEASURE')).to eq(2.5)
    end

    # A zero load ceiling never finds room against a load average that is never zero, so the
    # run pauses and stands there with nothing on the screen but a pause.
    it 'refuses zero' do
      ENV['MEASURE'] = '0'
      expect { described_class.decimal('MEASURE') }.to raise_error(ArgumentError, /MEASURE/)
    end

    it 'refuses a word' do
      ENV['MEASURE'] = 'alto'
      expect { described_class.decimal('MEASURE') }.to raise_error(ArgumentError, /MEASURE/)
    end
  end
end
