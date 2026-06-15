require 'rails_helper'

RSpec.describe Webhooks::WhatsappEventsJob do
  subject(:job) { described_class }

  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:params)  do
    {
      object: 'whatsapp_business_account',
      phone_number: channel.phone_number,
      entry: [{
        changes: [
          {
            value: {
              metadata: {
                phone_number_id: channel.provider_config['phone_number_id'],
                display_phone_number: channel.phone_number.delete('+')
              }
            }
          }
        ]
      }]
    }
  end
  let(:process_service) { double }

  before do
    allow(process_service).to receive(:perform)
  end

  it 'enqueues the job on the high queue' do
    # WhatsApp webhooks carry interactive flows (QR pairing handshake,
    # incoming customer messages) — they must not sit behind background
    # work on :low when the queue is backed up.
    expect { job.perform_later(params) }.to have_enqueued_job(described_class)
      .with(params)
      .on_queue('high')
  end

  describe 'race condition handling on the async path' do
    # The controller's `perform_sync` rescue covers webhooks delivered with
    # `awaitResponse: true`. Webhooks delivered async (most of the volume)
    # land on Sidekiq directly, so the job itself needs to retry when the
    # `SendReplyJob` hasn't persisted the `source_id` yet.
    it 'has retry_on registered for MessageNotFoundError' do
      handler = described_class.rescue_handlers.find do |klass, _|
        klass == 'Whatsapp::BaileysHandlers::MessagesUpdate::MessageNotFoundError'
      end

      expect(handler).to be_present
    end

    it 'logs and discards instead of dying in DeadSet when retries exhaust' do
      # After 4 attempts the source_id will never appear: most of these
      # are outgoing echoes whose `messages.upsert` was lost upstream.
      # Verify the retry_on block swallows the exception instead of
      # letting it surface as an unhandled error.
      allow(Rails.logger).to receive(:info)

      error_class = Whatsapp::BaileysHandlers::MessagesUpdate::MessageNotFoundError
      error = error_class.new('source_id not found')

      handler = described_class.rescue_handlers.find { |klass, _| klass == error_class.to_s }
      internal_block = handler.last

      job_instance = described_class.new
      # `executions_for` keys by the stringified Array of exception classes
      # and pre-increments before comparing. Seed it at 3 so the next call
      # bumps to 4, equalling `attempts`, and routes into the discard branch.
      job_instance.exception_executions = { [error_class].to_s => 3 }

      expect { job_instance.instance_exec(error, &internal_block) }.not_to raise_error
      expect(Rails.logger).to have_received(:info).with(/discarding messages.update for unknown source_id/)
    end
  end

  context 'when whatsapp_cloud provider' do
    it 'enqueue Whatsapp::IncomingMessageWhatsappCloudService' do
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new)
      job.perform_now(params)
    end

    it 'will not enqueue message jobs based on phone number in the URL if the entry payload is not present' do
      params = {
        object: 'whatsapp_business_account',
        phone_number: channel.phone_number,
        entry: [{ changes: [{}] }]
      }
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new)
      allow(Whatsapp::IncomingMessageService).to receive(:new)

      expect(Whatsapp::IncomingMessageWhatsappCloudService).not_to receive(:new)
      expect(Whatsapp::IncomingMessageService).not_to receive(:new)
      job.perform_now(params)
    end

    it 'will not enqueue Whatsapp::IncomingMessageWhatsappCloudService if channel reauthorization required' do
      channel.prompt_reauthorization!
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(Whatsapp::IncomingMessageWhatsappCloudService).not_to receive(:new)
      job.perform_now(params)
    end

    it 'will not enqueue if channel is not present' do
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      allow(Whatsapp::IncomingMessageService).to receive(:new).and_return(process_service)

      expect(Whatsapp::IncomingMessageWhatsappCloudService).not_to receive(:new)
      expect(Whatsapp::IncomingMessageService).not_to receive(:new)
      job.perform_now(phone_number: 'random_phone_number')
    end

    it 'will not enqueue Whatsapp::IncomingMessageWhatsappCloudService if account is suspended' do
      account = channel.account
      account.update!(status: :suspended)
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      allow(Whatsapp::IncomingMessageService).to receive(:new).and_return(process_service)

      expect(Whatsapp::IncomingMessageWhatsappCloudService).not_to receive(:new)
      expect(Whatsapp::IncomingMessageService).not_to receive(:new)
      job.perform_now(params)
    end

    it 'logs a warning when channel is inactive' do
      channel.prompt_reauthorization!
      allow(Rails.logger).to receive(:warn)

      expect(Rails.logger).to receive(:warn).with("Inactive WhatsApp channel: #{channel.phone_number}")
      job.perform_now(params)
    end

    it 'logs a warning with unknown phone number when channel does not exist' do
      unknown_phone = '+1234567890'
      allow(Rails.logger).to receive(:warn)

      expect(Rails.logger).to receive(:warn).with("Inactive WhatsApp channel: unknown - #{unknown_phone}")
      job.perform_now(phone_number: unknown_phone)
    end
  end

  context 'when default provider' do
    it 'enqueue Whatsapp::IncomingMessageService' do
      stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
      channel.update!(provider: 'default')
      allow(Whatsapp::IncomingMessageService).to receive(:new).and_return(process_service)
      expect(Whatsapp::IncomingMessageService).to receive(:new)
      job.perform_now(params)
    end
  end

  context 'when whatsapp business params' do
    it 'enqueue Whatsapp::IncomingMessageWhatsappCloudService based on the number in payload' do
      other_channel = create(:channel_whatsapp, phone_number: '+1987654', provider: 'whatsapp_cloud', sync_templates: false,
                                                validate_provider_config: false)
      wb_params = {
        phone_number: channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [
          {
            changes: [
              {
                value: {
                  metadata: {
                    phone_number_id: other_channel.provider_config['phone_number_id'],
                    display_phone_number: other_channel.phone_number.delete('+')
                  }
                }
              }
            ]
          }
        ]
      }
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).with(inbox: other_channel.inbox, params: wb_params)
      job.perform_now(wb_params)
    end

    it 'creates a reaction message flagged with is_reaction' do
      other_channel = create(:channel_whatsapp, phone_number: '+1987654', provider: 'whatsapp_cloud', sync_templates: false,
                                                validate_provider_config: false)
      wb_params = {
        phone_number: channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [{
          changes: [{
            value: {
              contacts: [{ profile: { name: 'Test Test' }, wa_id: '1111981136571' }],
              messages: [{
                from: '1111981136571', id: 'wamid.REACTION_ID',
                reaction: { message_id: 'wamid.ORIGINAL_ID', emoji: '👍' },
                timestamp: '1664799904', type: 'reaction'
              }],
              metadata: {
                phone_number_id: other_channel.provider_config['phone_number_id'],
                display_phone_number: other_channel.phone_number.delete('+')
              }
            }
          }]
        }]
      }.with_indifferent_access

      expect do
        Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: other_channel.inbox, params: wb_params).perform
      end.to change(Message, :count).by(1)

      reaction_message = Message.find_by(source_id: 'wamid.REACTION_ID')
      expect(reaction_message.content).to eq('👍')
      expect(reaction_message.content_attributes['is_reaction']).to be true
    end

    it 'skips reaction messages when the emoji is blank (reaction removal)' do
      other_channel = create(:channel_whatsapp, phone_number: '+1987654', provider: 'whatsapp_cloud', sync_templates: false,
                                                validate_provider_config: false)
      wb_params = {
        phone_number: channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [{
          changes: [{
            value: {
              contacts: [{ profile: { name: 'Test Test' }, wa_id: '1111981136571' }],
              messages: [{
                from: '1111981136571', id: 'wamid.REACTION_REMOVAL_ID',
                reaction: { message_id: 'wamid.ORIGINAL_ID', emoji: '' },
                timestamp: '1664799904', type: 'reaction'
              }],
              metadata: {
                phone_number_id: other_channel.provider_config['phone_number_id'],
                display_phone_number: other_channel.phone_number.delete('+')
              }
            }
          }]
        }]
      }.with_indifferent_access

      expect do
        Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: other_channel.inbox, params: wb_params).perform
      end.to not_change(Message, :count).and not_change(Contact, :count)
    end

    it 'ignore request_welcome type message, would not create contact or conversation' do
      other_channel = create(:channel_whatsapp, phone_number: '+1987654', provider: 'whatsapp_cloud', sync_templates: false,
                                                validate_provider_config: false)
      wb_params = {
        phone_number: channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [{
          changes: [{
            value: {
              messages: [{
                from: '1111981136571', timestamp: '1664799904', type: 'request_welcome'
              }],
              metadata: {
                phone_number_id: other_channel.provider_config['phone_number_id'],
                display_phone_number: other_channel.phone_number.delete('+')
              }
            }
          }]
        }]
      }.with_indifferent_access
      expect do
        Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: other_channel.inbox, params: wb_params).perform
      end.not_to change(Contact, :count)

      expect do
        Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: other_channel.inbox, params: wb_params).perform
      end.not_to change(Conversation, :count)
    end

    it 'will not enque Whatsapp::IncomingMessageWhatsappCloudService when invalid phone number id' do
      other_channel = create(:channel_whatsapp, phone_number: '+1987654', provider: 'whatsapp_cloud', sync_templates: false,
                                                validate_provider_config: false)
      wb_params = {
        phone_number: channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [
          {
            changes: [
              {
                value: {
                  metadata: {
                    phone_number_id: 'random phone number id',
                    display_phone_number: other_channel.phone_number.delete('+')
                  }
                }
              }
            ]
          }
        ]
      }
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(Whatsapp::IncomingMessageWhatsappCloudService).not_to receive(:new).with(inbox: other_channel.inbox, params: wb_params)
      job.perform_now(wb_params)
    end
  end
end
