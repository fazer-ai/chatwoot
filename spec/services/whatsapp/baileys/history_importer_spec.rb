require 'rails_helper'

describe Whatsapp::Baileys::HistoryImporter do
  let!(:whatsapp_channel) do
    create(:channel_whatsapp,
           provider: 'baileys',
           provider_config: { webhook_verify_token: 'valid_token' },
           validate_provider_config: false,
           received_messages: false)
  end
  let(:inbox) { whatsapp_channel.inbox }
  let(:phone) { '5511912345678' }
  let(:lid) { '12345678' }
  let(:jid) { "#{lid}@lid" }

  def raw_message(id, sent_at:, body: "message #{id}", from_me: false, message: nil)
    {
      key: { id: id, remoteJid: jid, remoteJidAlt: "#{phone}@s.whatsapp.net", fromMe: from_me, addressingMode: 'lid' },
      pushName: 'June',
      messageTimestamp: sent_at.to_i,
      message: message || { conversation: body }
    }.with_indifferent_access
  end

  def import(messages, watermark: nil, requested: true)
    described_class.new(
      inbox: inbox,
      params: { messages: messages, watermark: watermark, requested: requested }
    ).perform
  end

  # Two seconds, not one: the provider clocks a message in whole seconds, so a date that
  # made the round trip through `messageTimestamp` has already lost its fraction before
  # anything here compares it against a freshly evaluated `N.days.ago`.
  before { stub_request(:get, /profile-picture-url/).to_return(status: 200, body: { data: { profilePictureUrl: nil } }.to_json) }

  describe 'the coverage split' do
    let(:watermark) { 3.days.ago }

    # Nobody has had the chance to read it, so it is late mail and belongs in the queue.
    it 'files a message newer than the boundary as open work' do
      import([raw_message('GAP', sent_at: 1.day.ago)], watermark: watermark)

      message = inbox.messages.find_by(source_id: 'GAP')
      expect(message.conversation).not_to be_resolved
      expect(message.created_at).to be_within(2.seconds).of(1.day.ago)
    end

    # Filed resolved from the start rather than resolved afterwards: a thread born in that
    # state fires no resolution reporting event and writes no "resolved by" line.
    it 'files a message older than the boundary as archive' do
      import([raw_message('OLD', sent_at: 10.days.ago)], watermark: watermark)

      message = inbox.messages.find_by(source_id: 'OLD')
      expect(message.conversation).to be_resolved
      expect(message.created_at).to be_within(2.seconds).of(10.days.ago)
    end

    it 'keeps the two halves in different threads' do
      import([raw_message('OLD', sent_at: 10.days.ago), raw_message('GAP', sent_at: 1.day.ago)], watermark: watermark)

      old = inbox.messages.find_by(source_id: 'OLD')
      gap = inbox.messages.find_by(source_id: 'GAP')
      expect(old.conversation_id).not_to eq(gap.conversation_id)
      expect(old.conversation).to be_resolved
      expect(gap.conversation).not_to be_resolved
    end

    # A first pairing has no coverage at all, so the whole pile is archive. With nobody
    # having asked, that means nothing is written: the privacy protection the outright
    # refusal used to provide.
    it 'writes nothing from a pile nobody asked for' do
      import([raw_message('OLD', sent_at: 10.days.ago)], watermark: nil, requested: false)

      expect(inbox.messages).to be_empty
    end

    # What arrived while the session was down is a different thing from an archive, and it
    # is the only part of an unprompted offer this inbox is missing.
    it 'keeps the gap of a pile nobody asked for' do
      import([raw_message('OLD', sent_at: 10.days.ago), raw_message('GAP', sent_at: 1.day.ago)],
             watermark: watermark, requested: false)

      expect(inbox.messages.pluck(:source_id)).to contain_exactly('GAP')
    end
  end

  it 'skips a message the inbox already holds' do
    conversation = create(:conversation, inbox: inbox, account: inbox.account)
    create(:message, conversation: conversation, inbox: inbox, source_id: 'A', content: 'stored')

    import([raw_message('A', sent_at: 2.days.ago, body: 'from the dump')], watermark: 3.days.ago)

    expect(inbox.messages.where(source_id: 'A').pluck(:content)).to eq(['stored'])
  end

  # The phone repeats itself inside a single dump.
  it 'writes one row for an id repeated in the same dump' do
    import([raw_message('A', sent_at: 2.days.ago), raw_message('A', sent_at: 2.days.ago)], watermark: 3.days.ago)

    expect(inbox.messages.where(source_id: 'A').count).to eq(1)
  end

  # What a report excluding backfilled traffic reads, and what keeps the coverage boundary
  # from moving under a later frame of the same sync.
  it 'marks the row as filed after the fact' do
    import([raw_message('A', sent_at: 2.days.ago)], watermark: 3.days.ago)

    expect(inbox.messages.find_by(source_id: 'A').content_attributes['imported']).to be(true)
  end

  it 'runs the live pipeline, so an echo is stored the way the live path stores one' do
    import([raw_message('MINE', sent_at: 2.days.ago, from_me: true)], watermark: 3.days.ago)

    message = inbox.messages.find_by(source_id: 'MINE')
    expect(message).to be_outgoing
    expect(message.sender).to be_nil
    expect(message.content_attributes['external_sender_name']).to eq('WhatsApp')
  end

  # The dump carries no media bytes and the bridge never fetched them, so the file the live
  # path downloads was never written. Every media message would be a round trip to a 404.
  it 'stores a media message unsupported without asking the provider for the file' do
    media = { imageMessage: { caption: 'a photo', mimetype: 'image/jpeg' } }
    import([raw_message('IMG', sent_at: 2.days.ago, message: media)], watermark: 3.days.ago)

    message = inbox.messages.find_by(source_id: 'IMG')
    expect(message.content_attributes['is_unsupported']).to be(true)
    expect(message.attachments).to be_empty
    expect(a_request(:get, %r{/media/})).not_to have_been_made
  end

  describe 'what an import may set off' do
    it 'never tells WhatsApp the messages were received' do
      channel = create(:channel_whatsapp, provider: 'baileys',
                                          provider_config: { webhook_verify_token: 'valid_token' },
                                          validate_provider_config: false)
      stub_request(:post, %r{/send-receipts}).to_return(status: 200, body: { data: {} }.to_json)

      described_class.new(
        inbox: channel.inbox,
        params: { messages: [raw_message('A', sent_at: 2.days.ago)], watermark: 3.days.ago, requested: true }
      ).perform

      expect(a_request(:post, %r{/send-receipts})).not_to have_been_made
    end

    it 'fires no automation, webhook or notification' do
      expect do
        import([raw_message('A', sent_at: 2.days.ago)], watermark: 3.days.ago)
      end.not_to have_enqueued_job(EventDispatcherJob)
    end
  end

  # A dump carries far more markers than messages, and the records behind a chat are
  # resolved once, before its first row is written. Measured on a real pairing: 519 of the
  # 614 threads it created held nothing at all.
  describe 'a chat the dump carries no message for' do
    let(:stub_message) do
      raw_message('STUB', sent_at: 10.days.ago).tap do |raw|
        raw.delete(:message)
        raw[:messageStubType] = 75
      end
    end

    it 'leaves no empty thread behind' do
      import([stub_message], watermark: 3.days.ago)

      expect(inbox.conversations).to be_empty
    end

    it 'creates no contact for it either' do
      import([stub_message], watermark: 3.days.ago)

      expect(inbox.contact_inboxes).to be_empty
    end

    it 'still files the chat whose dump mixes markers with messages' do
      import([stub_message, raw_message('REAL', sent_at: 10.days.ago)], watermark: 3.days.ago)

      expect(inbox.messages.pluck(:source_id)).to contain_exactly('REAL')
      expect(inbox.conversations.count).to eq(1)
    end
  end

  describe 'the stamps the suppressed callbacks would have kept' do
    it 'sorts the thread by the newest message it imported, not by the import' do
      import([raw_message('A', sent_at: 10.days.ago), raw_message('B', sent_at: 9.days.ago)], watermark: 11.days.ago)

      conversation = inbox.messages.find_by(source_id: 'B').conversation
      expect(conversation.last_activity_at).to be_within(2.seconds).of(9.days.ago)
    end

    # A thread this run opened is born stamped "waiting since now", which is wrong about a
    # message from last week.
    it 'dates the queue clock from the oldest unanswered message' do
      import([raw_message('A', sent_at: 2.days.ago), raw_message('B', sent_at: 1.day.ago)], watermark: 3.days.ago)

      conversation = inbox.messages.find_by(source_id: 'A').conversation
      expect(conversation.waiting_since).to be_within(2.seconds).of(2.days.ago)
    end

    # `handle_resolved_status_change` clears the clock on a thread that *becomes* resolved,
    # and an archive thread is born resolved instead, so nothing ever clears the stamp
    # `ensure_waiting_since` writes at creation. `Conversation.unattended` reads
    # `waiting_since` with no status of its own, so the whole archive would be filed as
    # unattended forever. Measured on a real pairing: 613 of 613 imported threads.
    it 'runs no queue clock on a thread it filed as archive' do
      import([raw_message('OLD', sent_at: 10.days.ago)], watermark: 3.days.ago)

      conversation = inbox.messages.find_by(source_id: 'OLD').conversation
      expect(conversation).to be_resolved
      expect(conversation.waiting_since).to be_nil
    end

    # An archive is filed resolved so it asks for nobody's attention, and a thread nobody
    # has ever opened counts every message as unread, so without this it would arrive
    # resolved and still wearing an unread badge.
    it 'draws no unread badge on a thread it filed as archive' do
      import([raw_message('OLD', sent_at: 10.days.ago)], watermark: 3.days.ago)

      conversation = inbox.messages.find_by(source_id: 'OLD').conversation
      expect(conversation.unread_incoming_messages).to be_empty
    end

    # A dump arrives in frames filed by separate workers, so the thread a later frame adds
    # to was created by a worker this one cannot see. Measured on a real pairing: two
    # threads left with a stamp three minutes behind their own newest row.
    it 'draws no badge on a thread an earlier frame created' do
      import([raw_message('FIRST', sent_at: 10.days.ago)], watermark: 3.days.ago)
      import([raw_message('LATER', sent_at: 9.days.ago)], watermark: 3.days.ago)

      conversation = inbox.messages.find_by(source_id: 'LATER').conversation
      expect(conversation.unread_incoming_messages).to be_empty
    end

    # On a thread that already existed an unread message is somebody's real backlog, and an
    # import has no business marking it read.
    it 'leaves an existing thread its own unread messages' do
      contact = create(:contact, account: inbox.account, phone_number: "+#{phone}", identifier: "#{lid}@lid")
      create(:contact_inbox, inbox: inbox, contact: contact, source_id: lid)
      conversation = create(:conversation, inbox: inbox, account: inbox.account, contact: contact,
                                           status: :resolved, agent_last_seen_at: nil)
      create(:message, conversation: conversation, inbox: inbox, account: inbox.account,
                       message_type: :incoming, content: 'unread')

      import([raw_message('OLD', sent_at: 10.days.ago)], watermark: 3.days.ago)

      expect(conversation.reload.unread_incoming_messages).not_to be_empty
    end

    # A thread that already existed holds something real, and an archive filed into it says
    # nothing about when it was last active: left to the ordinary callback, an import would
    # drag a conversation answered this morning back to last year and to the bottom of the
    # list.
    it 'never drags an existing thread backwards' do
      contact = create(:contact, account: inbox.account, phone_number: "+#{phone}", identifier: "#{lid}@lid")
      create(:contact_inbox, inbox: inbox, contact: contact, source_id: lid)
      conversation = create(:conversation, inbox: inbox, account: inbox.account, contact: contact,
                                           last_activity_at: 1.hour.ago)

      import([raw_message('A', sent_at: 10.days.ago)], watermark: 3.days.ago)

      expect(inbox.messages.find_by(source_id: 'A').conversation_id).to eq(conversation.id)
      expect(conversation.reload.last_activity_at).to be_within(2.seconds).of(1.hour.ago)
    end
  end

  # Not filed: they mutate a row that has to exist, and replaying them out of a dump either
  # no-ops or acts on a row a later message in the same dump has not written yet.
  it 'skips the entries that are not messages' do
    revoke = { protocolMessage: { type: 'REVOKE', key: { id: 'TARGET' } } }
    import([raw_message('REV', sent_at: 2.days.ago, message: revoke)], watermark: 3.days.ago)

    expect(inbox.messages).to be_empty
  end
end
