require 'rails_helper'
require 'rake'

# The tasks are the entry point, and only the services behind them were covered. Two bugs
# shipped in this call path at once -- reading the run's cursor before the run existed, and
# handing an already-built policy back to its own builder -- and no service spec could see
# either. These invoke the tasks the way an operator does.
# rubocop:disable RSpec/DescribeClass -- the subject is two rake tasks, not a class
describe 'the import rake tasks' do
  let(:account) { create(:account) }
  # The trait, not the bare factory: the tasks refuse a channel whose IMAP is off, which
  # is what the bare factory builds.
  let(:channel) { create(:channel_email, :imap_email, account: account) }
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
       SAMPLE FROM_PART FORM_ADDRESS FORM_SENDER_NAME IMAP_DISABLED_OK SINCE UNTIL].each { |key| ENV.delete(key) }
  end

  # `imap_enabled` is what stops Chatwoot polling a mailbox. A task that connects anyway is
  # spending credentials somebody turned off, and the settings behind a disabled channel are
  # nobody's job to keep current -- which arrives as a login error rather than as a line
  # saying what is wrong.
  # An `ALL` search on an inbox the live job is also polling selects mail that arrived a
  # minute ago. Filed here it is written silently, its conversation is born resolved, and the
  # poller then skips the source id as already stored: a customer who wrote this morning is
  # filed as history and never reaches an agent, with no error anywhere.
  describe 'the line between a history import and a second poller' do
    it 'stops before today unless told otherwise' do
      expect(ImapImportOptions.terms).to eq(['ALL', 'BEFORE', Date.current.strftime('%d-%b-%Y')])
    end

    it 'keeps the cutoff beside SINCE rather than replacing it' do
      ENV['SINCE'] = '01-Jan-2023'
      expect(ImapImportOptions.terms).to eq(['SINCE', '01-Jan-2023', 'BEFORE', Date.current.strftime('%d-%b-%Y')])
    end

    it 'moves the line where the operator asks for it' do
      ENV['UNTIL'] = '01-Jun-2024'
      expect(ImapImportOptions.terms).to eq(%w[ALL BEFORE 01-Jun-2024])
    end

    it 'tells the operator where the line is' do
      expect { Rake::Task['imap:import'].invoke }.to output(/Ate:\s+antes de/).to_stdout
    end
  end

  describe 'a channel whose IMAP integration is off' do
    let(:channel) { create(:channel_email, account: account) }

    it 'is refused by imap:import' do
      expect { Rake::Task['imap:import'].invoke }.to raise_error(SystemExit)
        .and output(/IMAP esta desligado/).to_stderr
    end

    it 'is refused by imap:scan too, which connects the same way' do
      expect { Rake::Task['imap:scan'].invoke }.to raise_error(SystemExit)
        .and output(/IMAP esta desligado/).to_stderr
    end

    # An archive inbox holds credentials on purpose and the live fetch job must stay away
    # from the mailbox they open, or the history arrives twice.
    it 'runs when the archive setup is stated out loud' do
      ENV['IMAP_DISABLED_OK'] = '1'
      expect { Rake::Task['imap:import'].invoke }.to output(/Retoma:/).to_stdout
    end
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

    # `Time.zone.parse` reads this as the year 1, which is a cutoff below every message in
    # the mailbox: the setting `ATTACHMENTS=all`, arrived at by typo, and the whole provider
    # budget spent on it.
    it 'refuses an ambiguous date rather than reading it as some other date' do
      ENV['ATTACHMENTS'] = '01/02/03'
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
        expect { Rake::Task['imap:import'].invoke }.to raise_error(ArgumentError, /#{key}/)
      end

      it "refuses a #{key} of zero, which reads as a setting and means a stopped run" do
        ENV[key] = '0'
        expect { Rake::Task['imap:import'].invoke }.to raise_error(ArgumentError, /#{key}/)
      end
    end

    # A count truncated to zero is worse than a rejected one: `LIMIT=0.5` would stop the run
    # at the first message while looking like the operator asked for it.
    it 'refuses a fractional LIMIT rather than truncating it' do
      ENV['LIMIT'] = '0.5'
      expect { Rake::Task['imap:import'].invoke }.to raise_error(ArgumentError, /LIMIT/)
    end

    # Rails' caster answers anything outside its own false list with true, `no` included, so
    # a lenient reading throws the resume point away while doing the opposite of what was
    # typed. `no` is a word an operator means, so it is honoured rather than refused.
    it 'reads a RESET_CURSOR of no as no' do
      Import::Email::Cursor.new(channel).tap { |cursor| cursor.advance('INBOX', 7, 42) }.flush
      ENV['RESET_CURSOR'] = 'no'
      expect { Rake::Task['imap:import'].invoke }.to output(/Retoma:\s+INBOX>42/).to_stdout
      expect(channel.reload.import_cursor).to be_present
    end

    it 'refuses a RESET_CURSOR it cannot read rather than guessing' do
      ENV['RESET_CURSOR'] = 'talvez'
      expect { Rake::Task['imap:import'].invoke }.to raise_error(ArgumentError, /RESET_CURSOR/)
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
      expect { Rake::Task['imap:scan'].invoke }.to raise_error(ArgumentError, /SAMPLE/)
    end

    # `SAMPLE=0.5` truncates to zero at the call site and the scan classifies nothing while
    # printing a finished projection.
    it 'refuses a fractional SAMPLE rather than truncating it to nothing' do
      ENV['SAMPLE'] = '0.5'
      expect { Rake::Task['imap:scan'].invoke }.to raise_error(ArgumentError, /SAMPLE/)
    end

    # The folder with the attachments is the one that exhausts the budget, and the one whose
    # absence the total does not show: a projection built on the folders that fit is not a
    # smaller projection, it is a wrong one.
    it 'says which folders it never sampled rather than printing a table that looks whole' do
      allow(imap).to receive(:list).and_return([Struct.new(:name, :attr).new('[Gmail]/Todos', [:All]),
                                                Struct.new(:name, :attr).new('[Gmail]/Spam', [:Junk])])
      spent = Import::Email::Pacer.new(budget_mb: 1, max_load: 99)
      allow(Import::Email::Pacer).to receive(:new).and_return(spent)
      allow(spent).to receive(:over_budget?).and_return(false, true)

      expect { Rake::Task['imap:scan'].invoke }
        .to output(/PROJECAO GERAL \(PARCIAL\).*ORCAMENTO ESGOTADO.*Spam/m).to_stdout
    end

    # A sample cut short is not a smaller sample, it is a different claim: the projection
    # multiplies it out over the whole folder either way, so one large first message can end
    # up describing a mailbox from a single result.
    it 'marks a folder whose sample the budget cut short' do
      allow(imap).to receive(:uid_search).and_return([1, 2, 3])
      allow(ImapImportOptions).to receive(:sample_kinds).and_return([{ customer: 1 }, false])
      expect { Rake::Task['imap:scan'].invoke }
        .to output(/PROJECAO GERAL \(PARCIAL\).*amostra parcial/m).to_stdout
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
    # The same trap as the IMAP task: zero against a load average that is never zero means
    # the run pauses and stands there with nothing on the screen but a pause.
    let(:ticket) do
      { 'Number' => 1, 'RequesterMail' => 'cliente@example.com',
        'DateCreation' => { '$date' => '2023-05-10T12:00:00Z' },
        'Interactions' => [{ '_id' => { '$binary' => { 'base64' => 'AAAAAAAAAAAAAAAA' } },
                             'Comments' => [{ 'Content' => 'Mensagem do ticket' }],
                             'Person' => { 'Type' => 0, 'Name' => 'Cliente' },
                             'DateCreation' => { '$date' => '2023-05-10T12:00:00Z' } }] }
    end
    let(:zip_path) { File.join(dir, 'export.zip') }
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    before do
      File.write(File.join(dir, 'part_0001.json'), [ticket].to_json)
      system('zip', '-jq', zip_path, File.join(dir, 'part_0001.json'), exception: true)
      ENV['ZIP'] = zip_path
    end

    it 'refuses a MAX_LOAD it cannot read, the same as the IMAP task does' do
      ENV['MAX_LOAD'] = 'muito'
      expect { Rake::Task['octadesk:import'].invoke }.to raise_error(ArgumentError, /MAX_LOAD/)
    end

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
