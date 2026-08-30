require 'rails_helper'

describe Import::Email::HistoryImporter do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, account: account) }
  let(:inbox) { channel.inbox }
  let(:importer) { described_class.new }
  let(:root_id) { 'raiz@example.com' }

  def mail(date:, message_id: "#{SecureRandom.hex(6)}@example.com", reply_to_root: false, headers: '')
    thread = reply_to_root ? "In-Reply-To: <#{root_id}>\r\nReferences: <#{root_id}>\r\n" : ''
    stamp = date ? "Date: #{date.rfc2822}\r\n" : ''
    Mail.read_from_string(
      "From: cliente@example.com\r\nTo: #{channel.email}\r\nSubject: Assunto do thread\r\n" \
      "Message-ID: <#{message_id}>\r\n#{stamp}#{thread}#{headers}\r\n" \
      'Uma mensagem com corpo suficiente para o pipeline aceitar sem reclamar de nada.'
    )
  end

  # The buffer exists for exactly this path, and every spec of the buffer itself exercises a
  # stand-in: left at the default this importer would send one bulk job per mail, which is
  # the flood the per-row guard was put in to stop wearing a different job class, and not
  # one of those specs would notice.
  describe 'what it owes the search index' do
    let(:relation) { double('Message relation') } # rubocop:disable RSpec/VerifiedDoubles
    let(:asked) { [] }

    before do
      allow(relation).to receive(:reindex)
      allow(ChatwootApp).to receive(:advanced_search_allowed?).and_return(true)
      allow(Message).to receive(:where) do |args|
        asked << args[:id]
        relation
      end
    end

    it 'holds the mail back rather than asking per message' do
      2.times { importer.import(mail(date: Time.zone.parse('2023-05-01 10:00')), channel) }
      expect(asked).to be_empty
    end

    # The buffer only makes sense if the per-row callback is off while it writes, and the
    # guard reads this rather than the level. Left unset, every row would be indexed twice.
    it 'takes the index on itself while it writes, which is what silences the callback' do
      seen = nil
      allow(importer).to receive(:settle_thread).and_wrap_original do |original|
        seen = Import::SilentWrite.indexing?
        original.call
      end
      importer.import(mail(date: Time.zone.parse('2023-05-01 10:00')), channel)
      expect(seen).to be(true)
    end

    # A later pass that fills in the attachments changes what the row is, and
    # `Messages::SearchDataPresenter` reads them. The flag silences the callback the update
    # would fire and this path settles nothing, so without asking by hand the flag would buy
    # silence and give nothing back.
    it 'owes the index the row a later pass enriched, not only the ones it created' do
      allow(importer).to receive_messages(skip_attachments?: false, incomplete?: true, fill_attachments: nil)
      stored = create(:message, account: account, inbox: inbox,
                                conversation: create(:conversation, account: account, inbox: inbox),
                                content_attributes: { imported: true, imported_text_only: true })
      importer.send(:enrich, mail(date: Time.zone.parse('2023-05-01 10:00')), channel, stored)
      importer.flush_search_index

      expect(asked).to eq([[stored.id]])
    end

    it 'hands over everything it held when the walk empties it' do
      2.times { importer.import(mail(date: Time.zone.parse('2023-05-01 10:00')), channel) }
      importer.flush_search_index
      expect(asked).to eq([inbox.messages.pluck(:id)])
    end
  end

  it 'files the message at the date it was sent, not at the date it was imported' do
    importer.import(mail(date: Time.zone.parse('2023-05-01 10:00')), channel)
    expect(inbox.messages.first.created_at).to eq(Time.zone.parse('2023-05-01 10:00'))
  end

  # Born resolved rather than transitioned into it: a transition fires a resolution event
  # and files the thread into today's figures.
  it 'opens the conversation already resolved and dated to the mail' do
    importer.import(mail(date: Time.zone.parse('2023-05-01 10:00')), channel)
    conversation = inbox.conversations.last
    expect(conversation.status).to eq('resolved')
    expect(conversation.created_at).to eq(Time.zone.parse('2023-05-01 10:00'))
  end

  it 'resolves the conversation even when the mail carries no usable date' do
    importer.import(mail(date: nil, headers: "Received: from a by b; Tue, 14 Mar 2023 10:22:31 -0300\r\n"), channel)
    conversation = inbox.conversations.last
    expect(conversation.status).to eq('resolved')
    expect(conversation.created_at).to eq(Time.zone.parse('2023-03-14 13:22:31 UTC'))
  end

  it 'marks what it wrote as imported, so reports can exclude it' do
    importer.import(mail(date: Time.zone.parse('2023-05-01 10:00')), channel)
    expect(inbox.messages.where(Import::IMPORTED_SQL).count).to eq(1)
  end

  # The live pipeline dedupes inside the thread it just picked, which is right for an
  # arrival and wrong for a replay: a mail whose References no longer resolve opens a fresh
  # conversation and the check then runs against a thread that is empty by construction.
  it 'writes nothing twice when the same mail comes round again' do
    message = mail(date: Time.zone.parse('2023-05-01 10:00'))
    importer.import(message, channel)
    expect { described_class.new.import(message, channel) }.not_to change(inbox.messages, :count)
  end

  describe 'a thread whose mail arrives out of order' do
    before do
      # IMAP hands out UIDs in arrival order, so the newest can be scanned first.
      importer.import(mail(date: Time.zone.parse('2023-06-10 10:00'), message_id: root_id), channel)
      importer.import(mail(date: Time.zone.parse('2023-01-05 08:00'), reply_to_root: true), channel)
      importer.import(mail(date: Time.zone.parse('2023-03-20 14:00'), reply_to_root: true), channel)
    end

    it 'keeps the thread together' do
      expect(inbox.conversations.count).to eq(1)
      expect(inbox.messages.count).to eq(3)
    end

    it 'sorts on the newest message rather than the last one scanned' do
      expect(inbox.conversations.last.last_activity_at).to eq(Time.zone.parse('2023-06-10 10:00'))
    end

    it 'dates the conversation from its oldest message rather than the one that opened it' do
      expect(inbox.conversations.last.created_at).to eq(Time.zone.parse('2023-01-05 08:00'))
    end
  end

  describe 'a mail that threads into a conversation somebody is working' do
    let(:contact_inbox) do
      ContactInboxWithContactBuilder.new(source_id: 'cliente@example.com', inbox: inbox,
                                         contact_attributes: { name: 'C', email: 'cliente@example.com' }).perform
    end
    let(:live) do
      conversation = Conversation.create!(account_id: account.id, inbox_id: inbox.id, status: :open,
                                          contact_id: contact_inbox.contact_id, contact_inbox_id: contact_inbox.id)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                       content: 'pergunta', source_id: root_id, created_at: 2.days.ago)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                       content: 'ja respondemos', created_at: 1.day.ago)
      conversation.reload
    end

    it 'does not move the waiting clock back to the archive, which would file it as unattended' do
      live.update_columns(waiting_since: nil) # rubocop:disable Rails/SkipsModelValidations -- the state an answered thread is in
      expect do
        importer.import(mail(date: Time.zone.parse('2023-05-15 09:00'), reply_to_root: true), channel)
      end.not_to(change { live.reload.waiting_since })
    end

    it 'leaves the creation date of a live thread alone' do
      expect do
        importer.import(mail(date: Time.zone.parse('2020-01-01 08:00'), reply_to_root: true), channel)
      end.not_to(change { live.reload.created_at })
    end
  end

  # Live traffic keeps this in `Message#update_contact_activity`, inside the after-create
  # callbacks the import suppresses wholesale. Left null, a contact with a decade of mail
  # sorts below one who has never written.
  describe 'when the contact last said anything' do
    it 'stamps it from the mail rather than from the clock' do
      importer.import(mail(date: Time.zone.parse('2023-05-01 10:00')), channel)
      expect(inbox.contacts.last.last_activity_at).to eq(Time.zone.parse('2023-05-01 10:00'))
    end

    it 'keeps the newest of the thread, whatever order the mail arrives in' do
      importer.import(mail(date: Time.zone.parse('2023-06-10 10:00'), message_id: root_id), channel)
      importer.import(mail(date: Time.zone.parse('2023-01-05 08:00'), reply_to_root: true), channel)
      expect(inbox.contacts.last.last_activity_at).to eq(Time.zone.parse('2023-06-10 10:00'))
    end

    # A contact somebody is talking to now has a real clock, and history must not move it.
    it 'never drags a live contact backwards' do
      importer.import(mail(date: Time.zone.parse('2023-05-01 10:00')), channel)
      contact = inbox.contacts.last
      contact.update!(last_activity_at: Time.zone.parse('2026-01-01 09:00'))
      described_class.new.import(mail(date: Time.zone.parse('2023-07-01 10:00'), reply_to_root: true), channel)
      expect(contact.reload.last_activity_at).to eq(Time.zone.parse('2026-01-01 09:00'))
    end
  end

  # A form posts as the company and names the customer in `Reply-To`. `MailPresenter`
  # takes the first address there is, so a form that lists its own routing address first
  # files the thread under the company -- and the dedupe is by Message-ID, so no later pass
  # revisits it.
  describe 'mail sent on somebody else behalf' do
    def delegated(reply_to)
      Mail.read_from_string(
        "From: #{channel.email}\r\nReply-To: #{reply_to}\r\nTo: #{channel.email}\r\n" \
        "Subject: contato pelo site\r\nMessage-ID: <#{SecureRandom.hex(6)}@example.com>\r\n" \
        "Date: Mon, 1 May 2023 10:00:00 -0300\r\n\r\n" \
        'Uma mensagem com corpo suficiente para o pipeline aceitar sem reclamar de nada.'
      )
    end

    it 'files it under the customer when the routing header names us first' do
      importer.import(delegated("#{channel.email}, cliente@example.com"), channel)
      expect(inbox.conversations.last.contact.email).to eq('cliente@example.com')
    end

    it 'files it under the customer when the routing header names only them' do
      importer.import(delegated('cliente@example.com'), channel)
      expect(inbox.conversations.last.contact.email).to eq('cliente@example.com')
    end

    it 'leaves an ordinary reply of ours alone' do
      importer.import(delegated(channel.email), channel)
      expect(inbox.conversations.last.contact.email).to eq(channel.email)
    end
  end

  describe 'attachments' do
    let(:with_attachment) do
      Mail.read_from_string(
        "From: cliente@example.com\r\nTo: #{channel.email}\r\nSubject: com anexo\r\n" \
        "Message-ID: <anexo@example.com>\r\nDate: Mon, 1 May 2023 10:00:00 -0300\r\nMIME-Version: 1.0\r\n" \
        "Content-Type: multipart/mixed; boundary=\"limite\"\r\n\r\n" \
        "--limite\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n" \
        "Corpo com texto suficiente para o pipeline aceitar sem reclamar.\r\n" \
        "--limite\r\nContent-Type: text/plain; charset=UTF-8\r\n" \
        "Content-Disposition: attachment; filename=\"nota.txt\"\r\n\r\nconteudo do anexo\r\n--limite--\r\n"
      )
    end

    it 'takes none by default, which is what keeps a first pass inside the byte budget' do
      described_class.new.import(with_attachment, channel)
      expect(inbox.messages.last.attachments).to be_empty
    end

    it 'takes them when the caller asks for all of them' do
      described_class.new(attachments: :all).import(with_attachment, channel)
      expect(inbox.messages.last.attachments).to be_present
    end

    it 'leaves behind what is older than the cutoff' do
      described_class.new(attachments: Time.zone.parse('2024-01-01')).import(with_attachment, channel)
      expect(inbox.messages.last.attachments).to be_empty
    end
  end

  # A first pass files a mailbox text-only to stay inside the provider budget; a later one
  # widens the cutoff. Without an enrichment path the second pass finds the Message-ID
  # stored, calls it done, and the attachments stay in a mailbox nobody reads again.
  describe 'widening the cutoff over mail already filed' do
    let(:with_attachment) do
      Mail.read_from_string(
        "From: cliente@example.com\r\nTo: #{channel.email}\r\nSubject: com anexo\r\n" \
        "Message-ID: <anexo@example.com>\r\nDate: Mon, 1 May 2023 10:00:00 -0300\r\nMIME-Version: 1.0\r\n" \
        "Content-Type: multipart/mixed; boundary=\"limite\"\r\n\r\n" \
        "--limite\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n" \
        "Corpo com texto suficiente para o pipeline aceitar sem reclamar.\r\n" \
        "--limite\r\nContent-Type: text/plain; charset=UTF-8\r\n" \
        "Content-Disposition: attachment; filename=\"nota.txt\"\r\n\r\nconteudo do anexo\r\n--limite--\r\n"
      )
    end

    def file_text_only
      described_class.new.import(with_attachment, channel, text_only: true)
      inbox.messages.last
    end

    it 'says on the row that its attachments were left behind' do
      expect(file_text_only.content_attributes['imported_text_only']).to be(true)
      expect(inbox.messages.where(Import::TEXT_ONLY_SQL).count).to eq(1)
    end

    it 'says nothing when the pass fetched the whole message' do
      described_class.new(attachments: :all).import(with_attachment, channel)
      expect(inbox.messages.where(Import::TEXT_ONLY_SQL).count).to eq(0)
    end

    it 'fetches the attachments onto the row a narrower pass already filed' do
      message = file_text_only
      widened = described_class.new(attachments: :all)
      expect { widened.import(with_attachment, channel) }.not_to change(inbox.messages, :count)
      expect(message.reload.attachments.count).to eq(1)
      expect(widened.outcome_kind).to eq(:enriquecidas)
    end

    it 'clears the flag, so a third pass has nothing left to do' do
      file_text_only
      described_class.new(attachments: :all).import(with_attachment, channel)
      third = described_class.new(attachments: :all)
      expect { third.import(with_attachment, channel) }.not_to change(Attachment, :count)
      expect(third.outcome_kind).to eq(:inalteradas)
    end

    it 'leaves it alone when the widened cutoff still excludes the message' do
      message = file_text_only
      described_class.new(attachments: Time.zone.parse('2024-01-01')).import(with_attachment, channel)
      expect(message.reload.attachments).to be_empty
      expect(message.content_attributes['imported_text_only']).to be(true)
    end

    # `text_only` returns nil when the structure names no text part worth taking, and the
    # backfill then fetches the whole message. The attachments are in hand and dropped
    # here, so this is the one path where the row's own writer is the one withholding.
    it 'marks the row when the whole message was fetched and the attachments dropped here' do
      described_class.new.import(with_attachment, channel)
      expect(inbox.messages.last.content_attributes['imported_text_only']).to be(true)
    end

    it 'marks nothing when the message carries no attachments to withhold' do
      plain = Mail.read_from_string(
        "From: cliente@example.com\r\nTo: #{channel.email}\r\nSubject: sem anexo\r\n" \
        "Message-ID: <simples@example.com>\r\nDate: Mon, 1 May 2023 10:00:00 -0300\r\n\r\n" \
        'Corpo com texto suficiente para o pipeline aceitar sem reclamar.'
      )
      described_class.new.import(plain, channel)
      expect(inbox.messages.where(Import::TEXT_ONLY_SQL).count).to eq(0)
    end

    it 'does not touch a row that was already complete' do
      described_class.new(attachments: :all).import(with_attachment, channel)
      again = described_class.new(attachments: :all)
      expect { again.import(with_attachment, channel) }.not_to change(Attachment, :count)
      expect(again.outcome_kind).to eq(:inalteradas)
    end
  end
end
