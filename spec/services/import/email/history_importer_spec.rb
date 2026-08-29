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
end
