require 'rails_helper'

describe Import::Octadesk::Backfill do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, account: account) }
  let(:inbox) { channel.inbox }
  let(:pacer) { Import::Email::Pacer.new(budget_mb: Float::INFINITY, max_load: 99) }
  let(:dir) { Dir.mktmpdir }
  let(:zip_path) { File.join(dir, 'export.zip') }

  def ticket(number)
    { 'Number' => number, 'RequesterMail' => "cliente#{number}@example.com",
      'DateCreation' => { '$date' => '2023-05-10T12:00:00Z' },
      'Interactions' => [{ '_id' => { '$binary' => { 'base64' => format('%016d', number) } },
                           'Comments' => [{ 'Content' => "Mensagem do ticket #{number}" }],
                           'Person' => { 'Type' => 0, 'Name' => 'Cliente' },
                           'DateCreation' => { '$date' => '2023-05-10T12:00:00Z' } }] }
  end

  before do
    File.write(File.join(dir, 'part_0001.json'), (1..3).map { |n| ticket(n) }.to_json)
    File.write(File.join(dir, 'part_0002.json'), (4..6).map { |n| ticket(n) }.to_json)
    system('zip', '-jq', zip_path, File.join(dir, 'part_0001.json'), File.join(dir, 'part_0002.json'), exception: true)
  end

  after { FileUtils.remove_entry(dir) }

  it 'walks every part and files what it finds' do
    run = described_class.new(inbox: inbox, zip_path: zip_path, pacer: pacer).perform
    expect(inbox.conversations.count).to eq(6)
    expect(run.stats[:lidos]).to eq(6)
  end

  it 'reports what the importer filed, not only what the walker read' do
    run = described_class.new(inbox: inbox, zip_path: zip_path, pacer: pacer).perform
    expect(run.stats).to include(lidos: 6, tickets: 6, mensagens: 6)
  end

  # A limit on reads cannot advance: the next run re-reads the same already-imported
  # tickets, writes nothing, and stops before reaching anything new.
  describe 'LIMIT' do
    it 'stops after that many newly imported tickets' do
      described_class.new(inbox: inbox, zip_path: zip_path, pacer: pacer, limit: 2).perform
      expect(inbox.conversations.count).to eq(2)
    end

    it 'continues where the previous run stopped when it is run again' do
      described_class.new(inbox: inbox, zip_path: zip_path, pacer: pacer, limit: 2).perform
      described_class.new(inbox: inbox, zip_path: zip_path, pacer: pacer, limit: 2).perform
      expect(inbox.conversations.count).to eq(4)
    end

    it 'reports that it stopped on the limit rather than on the end of the export' do
      run = described_class.new(inbox: inbox, zip_path: zip_path, pacer: pacer, limit: 2).perform
      expect(run.stopped_by).to eq(:limite)
    end
  end

  describe 'FROM_PART' do
    it 'skips the parts before the one it names' do
      run = described_class.new(inbox: inbox, zip_path: zip_path, pacer: pacer, from_part: 'part_0002.json').perform
      expect(inbox.conversations.count).to eq(3)
      expect(run.stats[:lidos]).to eq(3)
    end

    # Left to drop_while, a typo starts at whatever sorts after it, skips everything
    # between, and reports the export exhausted.
    it 'refuses a name that is not a member of the archive' do
      expect { described_class.new(inbox: inbox, zip_path: zip_path, pacer: pacer, from_part: 'part_0007z.json').parts }
        .to raise_error(ArgumentError, /is not a member of this export/)
    end
  end

  it 'reports a ticket it could not read without stopping the run' do
    File.write(File.join(dir, 'part_0003.json'), [{ 'Number' => 7 }].to_json)
    system('zip', '-jq', zip_path, File.join(dir, 'part_0003.json'), exception: true)
    run = described_class.new(inbox: inbox, zip_path: zip_path, pacer: pacer).perform
    expect(run.stats[:lidos]).to eq(7)
    expect(inbox.conversations.count).to eq(6)
  end
end
