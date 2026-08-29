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
  end
end
