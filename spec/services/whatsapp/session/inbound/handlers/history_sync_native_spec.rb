require 'rails_helper'

# The connector's slices: one chat each, typed by `sync`, with the chat's name and whether
# the phone has anything older.
RSpec.describe Whatsapp::Session::Inbound::Handlers::HistorySync do
  let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:model) { Whatsapp::Session::Model }
  let(:slots) { Whatsapp::Session::Inbound::ImportSlots }
  let(:phone) { '5541999990000' }
  let(:lid) { '182736451928374' }
  let(:chat) { model::Address.phone(phone) }
  let(:sender) { model::Party.new(phone: phone, lid: lid, push_name: 'Ana Souza') }

  after { Redis::Alfred.delete(slots::KEY) }

  def historical(id, at, chat: self.chat, content: nil)
    model::InboundMessage.new(
      id: id, chat: chat, sender: sender, from_me: false, timestamp: (at.to_f * 1000).to_i,
      content: content || model::Content::Text.new(body: "mensagem #{id}")
    )
  end

  def slice(messages, sync: 'on_demand', chat: self.chat, name: nil, exhausted: nil)
    data = { 'sync' => sync, 'chat' => chat.to_h, 'messages' => messages.map(&:to_h) }
    data['name'] = name if name
    data['exhausted'] = exhausted unless exhausted.nil?
    model::Event.build(model::Events::HistorySync.new(kind: 'messages', data: data))
  end

  def dispatch(frame) = Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, frame)
  def deliver(frame) = perform_enqueued_jobs(only: Whatsapp::Session::HistoryImportJob) { dispatch(frame) }
  def import_jobs = enqueued_jobs.select { |job| job['job_class'] == 'Whatsapp::Session::HistoryImportJob' }

  def threads_of(contact, source_id, statuses)
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: source_id)
    statuses.map do |status|
      create(:conversation, inbox: inbox, account: inbox.account, contact: contact, contact_inbox: contact_inbox, status: status)
    end
  end

  def a_contact(number = phone, **attributes)
    create(:contact, account: inbox.account, phone_number: "+#{number}", **attributes)
  end

  def cover!(at)
    other = create(:conversation, inbox: inbox, account: inbox.account)
    create(:message, conversation: other, inbox: inbox, account: inbox.account, source_id: 'LIVE00', created_at: at)
  end

  def exhausted?(conversation) = conversation.reload.additional_attributes&.dig('history_exhausted') == true

  describe 'off the consumer thread' do
    let(:frame) { slice(Array.new(100) { |index| historical(format('3EB0S%03d', index), (200 - index).minutes.ago) }, sync: 'recent') }

    before { channel.update!(provider_config: channel.provider_config.merge('history_sync' => true)) }

    it 'queues one import for the slice and writes nothing on the thread that read it' do
      expect(dispatch(frame)).to eq(:handled)

      expect(inbox.messages.count).to eq(0)
      expect(import_jobs.size).to eq(1)

      perform_enqueued_jobs(only: Whatsapp::Session::HistoryImportJob)
      expect(inbox.messages.count).to eq(100)
    end

    it 'waits for an import slot, and files the slice once one is given back' do
      tokens = Array.new(slots.concurrency) { |index| "held-#{index}" }
      Redis::Alfred.with { |conn| tokens.each { |token| conn.zadd(slots::KEY, Time.now.to_f + 300, token) } }

      dispatch(frame)
      perform_enqueued_jobs(only: Whatsapp::Session::HistoryImportJob, queue: 'low')

      expect(inbox.messages.count).to eq(0)
      expect(import_jobs.map { |job| job['queue_name'] }).to eq([slots::WAITING_QUEUE])

      Redis::Alfred.with { |conn| conn.zrem(slots::KEY, tokens.first) }
      perform_enqueued_jobs(only: Whatsapp::Session::HistoryImportJob)
      expect(inbox.messages.count).to eq(100)
    end
  end

  describe 'the end of the history' do
    # WhatsApp's answer to a request for a chat with nothing older is an empty slice that
    # says so, and the thread has to stop offering the button.
    it 'marks every thread of the chat, however the answer addresses it' do
      by_phone = threads_of(a_contact, phone, %i[resolved open])
      other_lid = '182736451928375'
      by_lid = threads_of(a_contact('5541999990001', identifier: "#{other_lid}@lid"), '5541999990001', %i[open])

      expect do
        expect(deliver(slice([], exhausted: true))).to eq(:handled)
        expect(deliver(slice([], chat: model::Address.lid(other_lid), exhausted: true))).to eq(:handled)
      end.not_to change(inbox.messages, :count)

      expect((by_phone + by_lid).map { |thread| exhausted?(thread) }).to eq([true, true, true])
    end

    it 'marks only when the slice says so, and after its messages are filed' do
      thread = threads_of(a_contact, phone, %i[open]).first
      first = [0, 1, 2].map { |minute| historical("3EB0A#{minute}", 5.days.ago + minute.minutes) }
      last = [3, 4].map { |minute| historical("3EB0A#{minute}", 6.days.ago + minute.minutes) }

      deliver(slice(first))
      expect(exhausted?(thread)).to be(false)

      deliver(slice(last, exhausted: true))
      expect(inbox.messages.where(source_id: (first + last).map(&:id)).count).to eq(5)
      expect(exhausted?(thread)).to be(true)

      expect { deliver(slice(last, exhausted: true)) }.not_to change(inbox.messages, :count)
      expect(exhausted?(thread)).to be(true)
    end
  end

  describe 'what the setting decides' do
    it 'files only what arrived while the session was down when nobody asked' do
      watermark = 4.days.ago
      cover!(watermark)
      older = [1, 2, 3].map { |days| historical("3EB0OLD#{days}", watermark - days.days) }
      newer = [1, 2].map { |hours| historical("3EB0NEW#{hours}", watermark + hours.hours) }

      expect { deliver(slice(older + newer, sync: 'recent')) }.to change(inbox.messages, :count).by(2)

      expect(inbox.messages.where(source_id: older.map(&:id))).to be_empty
      expect(inbox.messages.where(source_id: newer.map(&:id)).map { |row| row.conversation.status }.uniq).to eq(['open'])
    end

    it 'archives the dump in silence when the setting is on' do
      channel.update!(provider_config: channel.provider_config.merge('history_sync' => true))
      cover!(1.day.ago)
      dump = [3, 1, 5, 2, 4].map { |days| historical("3EB0ARC#{days}", (days + 1).days.ago) }

      expect { deliver(slice(dump, sync: 'bootstrap')) }.not_to change(Notification, :count)

      rows = inbox.messages.where(source_id: dump.map(&:id)).order(:created_at)
      expect(rows.map(&:conversation_id).uniq.size).to eq(1)
      expect(rows.first.conversation.status).to eq('resolved')
      expect(rows.map(&:source_id)).to eq(dump.sort_by(&:timestamp).map(&:id))
      rows.each do |row|
        sent = dump.find { |item| item.id == row.source_id }.timestamp / 1000.0
        expect(row.created_at).to be_within(1.second).of(Time.zone.at(sent))
      end
    end
  end

  describe 'who sees it land' do
    before do
      channel.update!(provider_config: channel.provider_config.merge('history_sync' => true))
      cover!(1.day.ago)
      threads_of(a_contact, phone, %i[open])
      allow(ActionCableListener.instance).to receive(:message_created)
    end

    it 'announces the answer somebody asked for from a thread' do
      deliver(slice([3, 4, 5].map { |days| historical("3EB0ASK#{days}", days.days.ago) }))

      expect(ActionCableListener.instance).to have_received(:message_created).at_least(:once)
      expect(inbox.messages.where(source_id: %w[3EB0ASK3 3EB0ASK4 3EB0ASK5]).count).to eq(3)
    end

    it 'files the full dump without a word to the dashboard' do
      deliver(slice([3, 4, 5].map { |days| historical("3EB0FUL#{days}", days.days.ago) }, sync: 'full'))

      expect(ActionCableListener.instance).not_to have_received(:message_created)
      expect(inbox.messages.where(source_id: %w[3EB0FUL3 3EB0FUL4 3EB0FUL5]).count).to eq(3)
    end
  end

  describe 'the name of a group' do
    let(:unnamed) { model::Address.group('120363400000000001') }
    let(:named) { model::Address.group('120363400000000002') }

    around { |example| with_modified_env(WHATSAPP_GROUPS_ENABLED: 'true') { example.run } }

    before do
      channel.update!(provider_config: channel.provider_config.merge('history_sync' => true))
      { unnamed => unnamed.id, named => 'Nome Antigo' }.each do |group, name|
        contact = create(:contact, account: inbox.account, name: name, identifier: group.to_jid, group_type: :group)
        create(:contact_inbox, contact: contact, inbox: inbox, source_id: group.id)
      end
      allow(Contacts::SyncGroupJob).to receive(:perform_later)
    end

    def group_slice(group, name, ids)
      slice(ids.each_with_index.map { |id, days| historical(id, (days + 1).days.ago, chat: group) }, chat: group, name: name)
    end

    it 'names a group filed under its own id, and leaves a named one alone' do
      deliver(group_slice(unnamed, 'Grupo WAC 407', %w[3EB0G11 3EB0G12]))
      deliver(group_slice(named, 'Outro Nome', %w[3EB0G21 3EB0G22]))

      expect(inbox.contact_inboxes.find_by(source_id: unnamed.id).contact.name).to eq('Grupo WAC 407')
      expect(inbox.contact_inboxes.find_by(source_id: named.id).contact.name).to eq('Nome Antigo')
      expect(inbox.messages.where(source_id: %w[3EB0G11 3EB0G12 3EB0G21 3EB0G22]).count).to eq(4)
    end
  end

  # The connector publishes a slice's media without a reference to its bytes, and nothing
  # follows it the way `media.download_failed` follows a live message.
  describe 'media in a slice' do
    let(:picture) { model::Content::Media.new(kind: 'image', mime: 'image/jpeg') }
    let(:messages) do
      [historical('3EB0M1', 3.days.ago), historical('3EB0M2', 3.days.ago + 1.minute, content: picture),
       historical('3EB0M3', 3.days.ago + 2.minutes)]
    end

    before { threads_of(a_contact, phone, %i[open]) }

    it 'files the picture as an unsupported bubble in its place, and fetches nothing' do
      deliver(slice(messages))

      rows = inbox.messages.where(source_id: %w[3EB0M1 3EB0M2 3EB0M3]).order(:created_at)
      expect(rows.map(&:source_id)).to eq(%w[3EB0M1 3EB0M2 3EB0M3])
      image = rows.second
      expect(image).to be_incoming
      expect(image.created_at).to be_within(1.second).of(3.days.ago + 1.minute)
      expect(image.content_attributes['is_unsupported']).to be(true)
      expect(image.attachments).to be_empty
      expect(enqueued_jobs.map { |job| job['job_class'] }).not_to include('Whatsapp::Session::MediaFetchJob')
    end
  end

  describe 'the same message twice' do
    it 'files each id once, whether it repeats inside the slice, across deliveries, or was stored live' do
      live = threads_of(a_contact, phone, %i[open]).first
      create(:message, conversation: live, inbox: inbox, account: inbox.account, source_id: '3EB0LIVE', created_at: 1.hour.ago)
      fresh = Array.new(97) { |index| historical(format('3EB0D%03d', index), (300 - index).minutes.ago) }
      frame = slice([historical('3EB0LIVE', 1.hour.ago)] + fresh + [fresh[10]])

      expect { deliver(frame) }.to change(inbox.messages, :count).by(97)
      expect { deliver(frame) }.not_to change(inbox.messages, :count)
      expect(inbox.messages.reorder(nil).group(:source_id).having('count(*) > 1').count).to be_empty
    end
  end
end
