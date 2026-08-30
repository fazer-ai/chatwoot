require 'rails_helper'

describe Import::Octadesk::Stream do
  let(:dir) { Dir.mktmpdir }
  let(:zip_path) { File.join(dir, 'export.zip') }

  before do
    File.write(File.join(dir, 'part_0002.json'), '[{"Number":2},{"Number":3}]')
    File.write(File.join(dir, 'part_0001.json'), '[{"Number":1}]')
    File.write(File.join(dir, 'leiame.txt'), 'nao e uma parte')
    system('zip', '-jq', zip_path, File.join(dir, 'part_0001.json'), File.join(dir, 'part_0002.json'),
           File.join(dir, 'leiame.txt'), exception: true)
  end

  after { FileUtils.remove_entry(dir) }

  it 'lists the json members in order and ignores everything else' do
    expect(described_class.new(zip_path).parts).to eq(%w[part_0001.json part_0002.json])
  end

  # An empty list walks nothing and prints "export exhausted", so a broken archive and a
  # finished import would be indistinguishable.
  it 'raises rather than reporting an unreadable archive as an empty one' do
    expect { described_class.new(File.join(dir, 'nao-existe.zip')).parts }
      .to raise_error(RuntimeError, /cannot read the archive/)
  end

  it 'yields one top-level object at a time, so a gigabyte part never lands whole' do
    yielded = []
    described_class.new(zip_path).each_object('part_0002.json') { |object| yielded << object }
    expect(yielded).to eq([{ 'Number' => 2 }, { 'Number' => 3 }])
  end

  it 'lets the caller stop reading part way, which is what a LIMIT does' do
    yielded = []
    described_class.new(zip_path).each_object('part_0002.json') do |object| # rubocop:disable Lint/UnreachableLoop -- that is the point
      yielded << object
      raise StopIteration
    end
    expect(yielded).to eq([{ 'Number' => 2 }])
  end

  # A member that lists but will not extract leaves stdout empty, which Oj accepts as a
  # well-formed nothing -- so the part reports zero tickets and the run moves on with every
  # number on the screen looking right.
  it 'raises rather than reporting an unextractable member as an empty one' do
    expect { described_class.new(zip_path).each_object('nao-esta-no-zip.json') { |_| nil } }
      .to raise_error(RuntimeError, /cannot read nao-esta-no-zip.json/)
  end

  # Stopping early closes the pipe and unzip dies of SIGPIPE, which is the caller getting
  # what it asked for rather than a failure.
  it 'does not mistake a caller that stopped early for a broken member' do
    expect do
      described_class.new(zip_path).each_object('part_0002.json') do |_| # rubocop:disable Lint/UnreachableLoop -- that is the point
        raise StopIteration
      end
    end.not_to raise_error
  end

  describe 'the shapes Mongo extended JSON wraps its scalars in' do
    it 'reads an id from either spelling' do
      expect(described_class.oid({ '$binary' => { 'base64' => 'QUJD' } })).to eq('QUJD')
      expect(described_class.oid({ '$oid' => 'abc123' })).to eq('abc123')
      expect(described_class.oid('já é uma string')).to eq('já é uma string')
    end

    it 'reads a date, and answers nil for anything that is not one' do
      expect(described_class.time({ '$date' => '2023-05-10T12:00:00Z' })).to eq(Time.zone.parse('2023-05-10T12:00:00Z'))
      expect(described_class.time(nil)).to be_nil
      expect(described_class.time({})).to be_nil
    end
  end

  # The keys are captured before the stack is popped; getting that backwards attaches every
  # nested object to the wrong parent.
  it 'keeps nested objects and arrays under the keys they belong to' do
    File.write(File.join(dir, 'part_0003.json'),
               '[{"Number":9,"Person":{"Type":1,"Name":"A"},"Comments":[{"Content":"x"},{"Content":"y"}]}]')
    system('zip', '-jq', zip_path, File.join(dir, 'part_0003.json'), exception: true)
    yielded = []
    described_class.new(zip_path).each_object('part_0003.json') { |object| yielded << object }
    expect(yielded).to eq([{ 'Number' => 9, 'Person' => { 'Type' => 1, 'Name' => 'A' },
                             'Comments' => [{ 'Content' => 'x' }, { 'Content' => 'y' }] }])
  end
end
