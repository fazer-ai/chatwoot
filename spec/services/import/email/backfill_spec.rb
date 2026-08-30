require 'rails_helper'

describe Import::Email::Backfill do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, account: account) }
  let(:inbox) { channel.inbox }
  let(:pacer) { Import::Email::Pacer.new(budget_mb: Float::INFINITY, max_load: 99) }

  # `sent` and `relay` are recognised so a scan can count them, and refused so a run cannot
  # file them: both would go through the incoming-only pipeline and come out backwards.
  describe 'the kinds a run may not take' do
    it 'refuses the mailbox own outgoing mail' do
      expect { described_class.new(inbox: inbox, kinds: %i[customer sent], pacer: pacer) }
        .to raise_error(ArgumentError, /sent/)
    end

    it 'refuses the ticketing system relay notifications' do
      expect { described_class.new(inbox: inbox, kinds: [:relay], pacer: pacer) }
        .to raise_error(ArgumentError, /relay/)
    end

    it 'accepts the ordinary case' do
      expect { described_class.new(inbox: inbox, kinds: [:customer], pacer: pacer) }.not_to raise_error
    end

    # A typo matches nothing, imports nothing, and advances the cursor over the whole
    # mailbox while the task reports it finished.
    it 'refuses a kind the classifier does not answer' do
      expect { described_class.new(inbox: inbox, kinds: %i[customer customers], pacer: pacer) }
        .to raise_error(ArgumentError, /customers/)
    end

    # `imap:scan` classifies everything and imports none of it.
    it 'accepts no kinds at all, which is what a scan asks for' do
      expect { described_class.new(inbox: inbox, kinds: [], pacer: pacer) }.not_to raise_error
    end
  end

  describe 'choosing folders' do
    let(:run) { described_class.new(inbox: inbox, kinds: [:customer], pacer: pacer) }
    let(:listed) { Struct.new(:name, :attr) }

    it 'walks the all-mail folder plus spam when the server advertises them' do
      imap = instance_double(Net::IMAP, list: [listed.new('[Gmail]/Todos', [:All]), listed.new('[Gmail]/Spam', [:Junk])])
      expect(run.folders(imap)).to eq(['[Gmail]/Todos', '[Gmail]/Spam'])
    end

    # Without the fallback a perfectly valid channel scans nothing, or scans only spam,
    # which looks like it worked.
    it 'falls back to INBOX on a server that advertises no special use' do
      imap = instance_double(Net::IMAP, list: [listed.new('INBOX', [:Hasnochildren])])
      expect(run.folders(imap)).to eq(['INBOX'])
    end

    it 'keeps spam beside INBOX rather than letting it stand in for the mail folder' do
      imap = instance_double(Net::IMAP, list: [listed.new('Junk', [:Junk])])
      expect(run.folders(imap)).to eq(%w[INBOX Junk])
    end
  end

  # Every pass re-walks the folder and asks what the inbox already holds. One query per
  # header is a round trip per message for the life of the import.
  describe 'skipping what the inbox already holds' do
    let(:run) { described_class.new(inbox: inbox, kinds: [:customer], pacer: pacer) }
    let(:stored_id) { 'ja-tenho@example.com' }
    let(:fetched) do
      [
        Struct.new(:attr).new({ 'UID' => 10, 'BODY[HEADER.FIELDS (MESSAGE-ID)]' => "Message-ID: <#{stored_id}>\r\n" }),
        Struct.new(:attr).new({ 'UID' => 11, 'BODY[HEADER.FIELDS (MESSAGE-ID)]' => "Message-ID: <novo@example.com>\r\n" }),
        Struct.new(:attr).new({ 'UID' => 12, 'BODY[HEADER.FIELDS (MESSAGE-ID)]' => "Subject: sem id\r\n" })
      ]
    end

    before do
      conversation = create(:conversation, account: account, inbox: inbox)
      create(:message, account: account, inbox: inbox, conversation: conversation, source_id: stored_id)
    end

    it 'returns only the uids it still has to fetch' do
      imap = instance_double(Net::IMAP, uid_fetch: fetched)
      expect(run.send(:unstored, imap, [10, 11, 12])).to eq([11])
    end

    it 'asks the database once for the whole batch' do
      imap = instance_double(Net::IMAP, uid_fetch: fetched)
      queries = 0
      subscription = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        queries += 1 if payload[:sql].include?('messages') && payload[:name].to_s.exclude?('SCHEMA')
      end
      run.send(:unstored, imap, [10, 11, 12])
      ActiveSupport::Notifications.unsubscribe(subscription)
      expect(queries).to eq(1)
    end

    it 'counts what it skipped and why' do
      imap = instance_double(Net::IMAP, uid_fetch: fetched)
      run.send(:unstored, imap, [10, 11, 12])
      expect(run.stats).to include(ja_importadas: 1, sem_message_id: 1)
    end

    # "Stored" and "nothing left to do" are the same question only under the default. A row
    # filed without its attachments is stored and incomplete, and skipping it here is what
    # would put the attachments out of reach of every later pass.
    describe 'a row a narrower pass filed without its attachments' do
      before do
        inbox.messages.find_by(source_id: stored_id)
             .update!(content_attributes: { imported: true, imported_text_only: true })
      end

      def stored_row_dated(at)
        inbox.messages.find_by(source_id: stored_id).update_column(:created_at, at) # rubocop:disable Rails/SkipsModelValidations
      end

      def from_2024
        described_class.new(inbox: inbox, kinds: [:customer], pacer: pacer,
                            attachments: Time.zone.parse('2024-01-01'))
      end

      it 'is still done when the run is not asking for attachments' do
        imap = instance_double(Net::IMAP, uid_fetch: fetched)
        expect(run.send(:unstored, imap, [10, 11, 12])).to eq([11])
      end

      it 'is work again when the run widens the cutoff' do
        widened = described_class.new(inbox: inbox, kinds: [:customer], pacer: pacer, attachments: :all)
        imap = instance_double(Net::IMAP, uid_fetch: fetched)
        expect(widened.send(:unstored, imap, [10, 11, 12])).to eq([10, 11])
      end

      # A cutoff is not `all`. An incomplete row below it is not work -- the importer
      # declines it at `skip_attachments?` -- so re-offering it buys nothing and costs a
      # full re-fetch of the message, on a run the byte budget is what ends. A decade of a
      # support mailbox sits below any cutoff worth setting.
      it 'stays done under a cutoff it sits below' do
        stored_row_dated(Time.zone.parse('2020-01-01'))
        imap = instance_double(Net::IMAP, uid_fetch: fetched)
        expect(from_2024.send(:unstored, imap, [10, 11, 12])).to eq([11])
      end

      it 'is work again when it sits above the cutoff' do
        stored_row_dated(Time.zone.parse('2025-06-01'))
        imap = instance_double(Net::IMAP, uid_fetch: fetched)
        expect(from_2024.send(:unstored, imap, [10, 11, 12])).to eq([10, 11])
      end

      # `unstored` never runs on a uid the cursor filtered out first, so letting the row
      # through here is worth nothing unless the mark is invalidated too.
      it 'is reachable at all, because the mark from the narrower pass no longer applies' do
        narrow = described_class.new(inbox: inbox, kinds: [:customer], pacer: pacer)
        narrow.cursor.advance('INBOX', 9, 100)
        narrow.cursor.flush
        widened = described_class.new(inbox: inbox.reload, kinds: [:customer], pacer: pacer, attachments: :all)
        expect(widened.cursor.unseen('INBOX', 9, [10, 11])).to eq([10, 11])
      end
    end
  end

  # net-imap 0.6 answers a rev2-capable server with an ESearchResult rather than an Array.
  # It carries `each` and `to_a` and none of `length`, `select` or `each_slice`, so the walk
  # breaks at the progress line, before it can report anything.
  describe 'a server that answers the search with something other than an array' do
    let(:run) { described_class.new(inbox: inbox, kinds: [:customer], pacer: pacer) }
    let(:esearch) do
      Class.new do
        def initialize(uids) = @uids = uids
        def to_a = @uids
        def each(&) = @uids.each(&)
      end
    end

    it 'walks it the same as an array' do
      imap = instance_double(Net::IMAP, list: [Struct.new(:name, :attr).new('INBOX', [:Hasnochildren])],
                                        examine: nil, responses: 7, uid_search: esearch.new([10, 11]), logout: nil)
      allow(run).to receive_messages(connect: imap, unstored: [], close: nil)
      expect { run.perform }.not_to raise_error
    end
  end

  # The download is a collaborator now, and its own spec builds it by hand with a hash that
  # is certainly there. What no spec of that class can see is whether the walker handed it
  # the run's own tallies, so this exercises the wiring on the path the default setting
  # takes: every message carrying an attachment goes through it.
  it 'counts a lean fetch into the tallies the run reports' do
    run = described_class.new(inbox: inbox, kinds: [:customer], pacer: pacer)
    run.instance_variable_set(:@progress, ->(*) {}) # `perform` sets this; `handle` is called here on its own
    leaf = Struct.new(:media_type, :subtype, :encoding, :param, :disposition, :size, keyword_init: true) # rubocop:disable Lint/StructNewOverride
    structure = Struct.new(:subtype, :parts, keyword_init: true) do
      def media_type = 'MULTIPART'
      def encoding = nil
      def param = nil
      def disposition = nil
      def size = 0
    end.new(subtype: 'MIXED',
            parts: [leaf.new(media_type: 'TEXT', subtype: 'PLAIN', encoding: '7BIT',
                             param: { 'CHARSET' => 'UTF-8' }, disposition: nil, size: 900),
                    leaf.new(media_type: 'IMAGE', subtype: 'PNG', encoding: 'BASE64', param: {},
                             disposition: Struct.new(:dsp_type, :param).new('ATTACHMENT'), size: 3_000_000)])
    header = "From: cliente@example.com\r\nTo: #{channel.email}\r\nSubject: com foto\r\n" \
             "Message-ID: <foto@example.com>\r\nDate: #{Time.zone.parse('2023-05-01 10:00').rfc2822}\r\n"
    imap = instance_double(Net::IMAP)
    allow(imap).to receive(:uid_fetch).with(10, ['BODY.PEEK[HEADER]', 'BODYSTRUCTURE', 'RFC822.SIZE'])
                                      .and_return([Struct.new(:attr).new({ 'BODY[HEADER]' => header, 'BODYSTRUCTURE' => structure,
                                                                           'RFC822.SIZE' => 3_100_000 })])
    allow(imap).to receive(:uid_fetch).with(10, 'BODY.PEEK[1]')
                                      .and_return([Struct.new(:attr).new({ 'BODY[1]' => 'Segue a foto do ingresso que comprei ontem.' })])

    expect(run.send(:handle, imap, 10)).to be(true)
    expect(run.stats[:sem_anexos]).to eq(1)
  end

  # A refused message is not a settled one. Marked as read it would be skipped by every
  # later pass, so the run that could not afford it is the run that has to leave its mark
  # below it -- and end there, because ending a pass is what the budget is for.
  it 'ends the pass below a message it cannot afford, without settling it' do
    tight = Import::Email::Pacer.new(budget_mb: 1, max_load: 99)
    run = described_class.new(inbox: inbox, kinds: [:customer], pacer: tight, attachments: :all)
    run.instance_variable_set(:@progress, ->(*) {})
    header = "From: cliente@example.com\r\nTo: #{channel.email}\r\nSubject: gigante\r\n" \
             "Message-ID: <gigante@example.com>\r\nDate: #{Time.zone.parse('2023-05-01 10:00').rfc2822}\r\n"
    imap = instance_double(Net::IMAP)
    allow(imap).to receive(:uid_fetch).with(10, ['BODY.PEEK[HEADER]', 'BODYSTRUCTURE', 'RFC822.SIZE'])
                                      .and_return([Struct.new(:attr).new({ 'BODY[HEADER]' => header, 'BODYSTRUCTURE' => nil,
                                                                           'RFC822.SIZE' => 5.megabytes })])

    expect(run.send(:handle, imap, 10)).to be(false)
    expect(run.stopped_by).to eq(:orcamento)
    expect(imap).not_to have_received(:uid_fetch).with(10, 'BODY.PEEK[]')
  end

  # A mark only means anything against the question that produced it, and the question is
  # narrower than the search terms.
  describe 'what invalidates a stored mark' do
    def mark(**)
      run = described_class.new(inbox: inbox, kinds: [:customer], pacer: pacer, **)
      run.cursor.advance('INBOX', 9, 100)
      run.cursor.flush
      run
    end

    def sees_the_mark?(**)
      run = described_class.new(inbox: inbox.reload, kinds: [:customer], pacer: pacer, **)
      run.cursor.unseen('INBOX', 9, [10, 200]) == [200]
    end

    # The default cutoff is a date, so it moves every midnight. Counted in the selection, a
    # run resumed the next day finds every mark stale, starts each folder at UID 0 and
    # spends the day's provider budget re-walking mail it has already declined -- on a
    # mailbox that takes weeks, an import that never finishes.
    it 'survives a cutoff that moved with the calendar' do
      mark(terms: %w[ALL BEFORE 29-Aug-2026])
      expect(sees_the_mark?(terms: %w[ALL BEFORE 30-Aug-2026])).to be(true)
    end

    # Widening SINCE backwards is how older, lower numbered mail becomes eligible under a
    # mark that would hide it.
    it 'is invalidated when the run reaches further back' do
      mark(terms: %w[SINCE 01-Jan-2024])
      expect(sees_the_mark?(terms: %w[SINCE 01-Jan-2020])).to be(false)
    end

    # `UIDVALIDITY` is unique inside one mailbox and commonly starts at 1, so a channel
    # repointed at another account can present a fresh folder whose stamp matches an old
    # mark, and everything below it is filtered out before the Message-ID check runs.
    it 'is invalidated when the channel is repointed at another mailbox' do
      mark
      channel.update!(imap_login: 'outra@example.com')
      expect(sees_the_mark?).to be(false)
    end
  end

  # The importer buffers a settlement at a time and something has to say when a run of them
  # is a batch. Wired here rather than asserted on the buffer, because what the buffer needs
  # is that somebody empties it.
  describe 'emptying what the importer owes the index' do
    let(:run) { described_class.new(inbox: inbox, kinds: [:customer], pacer: pacer) }
    let(:importer) { run.send(:instance_variable_get, :@importer) }

    it 'empties it at the batch boundary the walk already has' do
      imap = instance_double(Net::IMAP, uid_fetch: [])
      expect(importer).to receive(:flush_search_index).at_least(:once)
      run.send(:walk, imap, [10, 11])
    end

    # An interrupted run leaves at most one batch buffered; a run that ends normally must
    # leave none, or the tail is missing from the index with nothing to say so.
    it 'empties it when the run ends, whatever ended it' do
      allow(run).to receive(:connect).and_raise(Net::IMAP::Error)
      expect(importer).to receive(:flush_search_index)
      expect { run.perform }.to raise_error(Net::IMAP::Error)
    end
  end

  # A message that raised is not settled. Marked as read it would be skipped by every later
  # pass, so a timeout or a malformed part would quietly cost a message forever.
  describe 'how far the cursor is allowed to move' do
    let(:run) { described_class.new(inbox: inbox, kinds: [:customer], pacer: pacer) }

    before do
      run.instance_variable_set(:@folder, 'INBOX')
      run.instance_variable_set(:@uidvalidity, 7)
    end

    it 'marks the whole batch when every message was settled' do
      allow(run).to receive_messages(unstored: [10, 11, 12], handle: true)
      run.send(:walk, instance_double(Net::IMAP), [10, 11, 12])
      expect(channel.reload.import_cursor.dig('INBOX', 'uid')).to eq(12)
    end

    it 'stops the mark below the first message it could not settle' do
      allow(run).to receive(:unstored).and_return([10, 11, 12])
      allow(run).to receive(:handle).and_return(true, false, true)
      run.send(:walk, instance_double(Net::IMAP), [10, 11, 12])
      expect(channel.reload.import_cursor.dig('INBOX', 'uid')).to eq(10)
    end

    it 'writes no mark at all when the first message already failed' do
      allow(run).to receive_messages(unstored: [10, 11], handle: false)
      run.send(:walk, instance_double(Net::IMAP), [10, 11])
      expect(channel.reload.import_cursor).to eq({})
    end

    # The run carries on past a message it could not settle, and the batches after it are
    # above the failure. Letting them advance buries the very uid the freeze exists to keep
    # reachable, and every later pass then starts above it.
    it 'keeps the mark frozen for the rest of the folder once a batch has failed' do
      stub_const("#{described_class}::HEADER_BATCH", 2)
      allow(run).to receive(:unstored) { |_, batch| batch }
      allow(run).to receive(:handle).and_return(true, false, true, true)
      run.send(:walk, instance_double(Net::IMAP), [10, 11, 12, 13])
      expect(channel.reload.import_cursor.dig('INBOX', 'uid')).to eq(10)
    end
  end
end
