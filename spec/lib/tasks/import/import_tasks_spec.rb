require 'rails_helper'
require 'rake'

# The tasks are the entry point, and only the services behind them were covered. Two bugs
# shipped in this call path at once -- reading the run's cursor before the run existed, and
# handing an already-built policy back to its own builder -- and no service spec could see
# either. These invoke the tasks the way an operator does.
# rubocop:disable RSpec/DescribeClass -- the subject is two rake tasks, not a class
describe 'the import rake tasks' do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, account: account) }
  let(:inbox) { channel.inbox }
  let(:imap) { instance_double(Net::IMAP) }
  let(:folder) { Struct.new(:name, :attr).new('INBOX', [:Hasnochildren]) }

  before do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task.tasks.each(&:reenable)
    ENV['INBOX_ID'] = inbox.id.to_s
    allow(Net::IMAP).to receive(:new).and_return(imap)
    allow(imap).to receive_messages(authenticate: nil, list: [folder], examine: nil,
                                    responses: 7, uid_search: [], logout: nil)
  end

  after do
    %w[INBOX_ID ZIP LIMIT ATTACHMENTS KINDS FOLDERS MAX_LOAD BUDGET_MB RESET_CURSOR
       SAMPLE FROM_PART FORM_ADDRESS FORM_SENDER_NAME].each { |key| ENV.delete(key) }
  end

  describe 'imap:import' do
    it 'runs with nothing but the inbox, which is the documented first call' do
      expect { Rake::Task['imap:import'].invoke }.to output(/Retoma:\s+do inicio/).to_stdout
    end

    it 'takes no attachments by default, which is what keeps a first pass inside the budget' do
      expect { Rake::Task['imap:import'].invoke }.to output(/Anexos:\s+nenhum/).to_stdout
    end

    it 'accepts a cutoff date' do
      ENV['ATTACHMENTS'] = '2024-01-01'
      expect { Rake::Task['imap:import'].invoke }.to output(/Anexos:\s+a partir de 2024-01-01/).to_stdout
    end

    it 'accepts all of them' do
      ENV['ATTACHMENTS'] = 'all'
      expect { Rake::Task['imap:import'].invoke }.to output(/Anexos:\s+todos/).to_stdout
    end

    it 'stops on a setting it cannot read rather than quietly taking none' do
      ENV['ATTACHMENTS'] = 'quinta-feira'
      expect { Rake::Task['imap:import'].invoke }.to raise_error(ArgumentError, /ATTACHMENTS/)
    end

    it 'reports where a previous pass got to' do
      Import::Email::Cursor.new(channel).tap { |cursor| cursor.advance('INBOX', 7, 42) }.flush
      expect { Rake::Task['imap:import'].invoke }.to output(/Retoma:\s+INBOX>42/).to_stdout
    end

    it 'forgets that mark when asked' do
      Import::Email::Cursor.new(channel).tap { |cursor| cursor.advance('INBOX', 7, 42) }.flush
      ENV['RESET_CURSOR'] = '1'
      expect { Rake::Task['imap:import'].invoke }.to output(/Retoma:\s+do inicio/).to_stdout
      expect(channel.reload.import_cursor).to eq({})
    end

    # `RESET_CURSOR=0` reads as "off" to whoever typed it. Honoured as "on" it throws away
    # the resume point on every invocation, and each pass re-walks the declined mail it had
    # already got past.
    it 'keeps the mark when the setting says not to reset' do
      Import::Email::Cursor.new(channel).tap { |cursor| cursor.advance('INBOX', 7, 42) }.flush
      ENV['RESET_CURSOR'] = '0'
      expect { Rake::Task['imap:import'].invoke }.to output(/Retoma:\s+INBOX>42/).to_stdout
      expect(channel.reload.import_cursor).to be_present
    end

    it 'refuses a kind it cannot file rather than filing it backwards' do
      ENV['KINDS'] = 'customer,sent'
      expect { Rake::Task['imap:import'].invoke }.to raise_error(ArgumentError, /sent/)
    end

    # `to_f` turns a typo into zero, and every one of these fails silently in the expensive
    # direction when it is zero: no budget stops before importing anything, no load ceiling
    # never finds room, so the run stands still forever against a host that always reports
    # some load.
    %w[MAX_LOAD BUDGET_MB LIMIT].each do |key|
      it "refuses a #{key} that is not a number" do
        ENV[key] = 'muito'
        expect { Rake::Task['imap:import'].invoke }.to raise_error(SystemExit)
      end

      it "refuses a #{key} of zero, which reads as a setting and means a stopped run" do
        ENV[key] = '0'
        expect { Rake::Task['imap:import'].invoke }.to raise_error(SystemExit)
      end
    end

    it 'refuses a kind the classifier does not answer, rather than importing nothing' do
      ENV['KINDS'] = 'customers'
      expect { Rake::Task['imap:import'].invoke }.to raise_error(ArgumentError, /customers/)
    end

    # A setting somebody wrote on purpose that means nothing: the run would classify the
    # whole mailbox, import none of it and report the folder finished.
    it 'refuses an empty KINDS rather than defaulting around it' do
      ENV['KINDS'] = ','
      expect { Rake::Task['imap:import'].invoke }.to raise_error(SystemExit)
    end
  end

  describe 'imap:scan' do
    it 'reports a projection and writes nothing' do
      expect { Rake::Task['imap:scan'].invoke }.to output(/PROJECAO GERAL/).to_stdout
      expect(inbox.messages.count).to eq(0)
    end

    # net-imap 0.6 answers a rev2-capable server with an ESearchResult, which has `to_a`
    # and no `length`. The scan reads `length` on the line after the search.
    it 'refuses a SAMPLE that is not a number, which would otherwise read as zero' do
      ENV['SAMPLE'] = 'muito'
      expect { Rake::Task['imap:scan'].invoke }.to raise_error(SystemExit)
    end

    it 'survives a server that answers the search with something other than an array' do
      esearch = Class.new do
        def initialize(uids) = @uids = uids
        def to_a = @uids
        def each(&) = @uids.each(&)
      end
      allow(imap).to receive(:uid_search).and_return(esearch.new([]))
      expect { Rake::Task['imap:scan'].invoke }.to output(/PROJECAO GERAL/).to_stdout
    end
  end

  # The scan downloads each sampled message whole, so the cap is a byte budget and not a
  # preference.
  describe 'ImapImportOptions.spread' do
    it 'takes everything when the folder is smaller than the sample' do
      expect(ImapImportOptions.spread((1..10).to_a, 400).length).to eq(10)
    end

    # Integer division makes the stride 1 for any folder between sample+1 and 2*sample-1,
    # so `SAMPLE=400` over 799 messages downloaded 799 of them.
    it 'never takes more than the sample it was given' do
      expect(ImapImportOptions.spread((1..799).to_a, 400).length).to eq(400)
    end

    it 'picks no uid twice' do
      picked = ImapImportOptions.spread((1..799).to_a, 400)
      expect(picked.uniq.length).to eq(picked.length)
    end

    it 'spreads them across the folder rather than taking the head' do
      picked = ImapImportOptions.spread((1..10_000).to_a, 10)
      expect(picked.first).to eq(1)
      expect(picked.last).to be > 9000
    end
  end

  describe 'octadesk:import' do
    let(:dir) { Dir.mktmpdir }
    let(:zip_path) { File.join(dir, 'export.zip') }
    let(:ticket) do
      { 'Number' => 1, 'RequesterMail' => 'cliente@example.com',
        'DateCreation' => { '$date' => '2023-05-10T12:00:00Z' },
        'Interactions' => [{ '_id' => { '$binary' => { 'base64' => 'AAAAAAAAAAAAAAAA' } },
                             'Comments' => [{ 'Content' => 'Mensagem do ticket' }],
                             'Person' => { 'Type' => 0, 'Name' => 'Cliente' },
                             'DateCreation' => { '$date' => '2023-05-10T12:00:00Z' } }] }
    end

    before do
      File.write(File.join(dir, 'part_0001.json'), [ticket].to_json)
      system('zip', '-jq', zip_path, File.join(dir, 'part_0001.json'), exception: true)
      ENV['ZIP'] = zip_path
    end

    after { FileUtils.remove_entry(dir) }

    it 'imports the export and reports what it filed rather than only what it read' do
      expect { Rake::Task['octadesk:import'].invoke }.to output(/tickets\s+1/).to_stdout
      expect(inbox.conversations.count).to eq(1)
    end

    it 'mirrors no attachments unless asked' do
      expect { Rake::Task['octadesk:import'].invoke }.to output(/Anexos:\s+nao/).to_stdout
    end

    # A presence check reads "0" as present, and the difference is hundreds of gigabytes.
    it 'reads a false value as off' do
      ENV['ATTACHMENTS'] = '0'
      expect { Rake::Task['octadesk:import'].invoke }.to output(/Anexos:\s+nao/).to_stdout
    end

    it 'reads 1 as on' do
      ENV['ATTACHMENTS'] = '1'
      expect { Rake::Task['octadesk:import'].invoke }.to output(/Anexos:\s+sim/).to_stdout
    end
  end
end
# rubocop:enable RSpec/DescribeClass
