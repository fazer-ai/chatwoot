require 'rails_helper'

RSpec.describe SendReplyJob do
  subject(:job) { described_class.perform_later(message) }

  let(:message) { create(:message) }

  it 'enqueues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .with(message)
      .on_queue('high')
  end

  context 'when the job is triggered on a new message' do
    let(:process_service) { double }

    before do
      allow(process_service).to receive(:perform)
    end

    def expect_mapped_service_to_perform(message, service_class_name)
      channel_name = message.conversation.inbox.channel.class.name
      mapped_class_name = described_class::CHANNEL_SERVICES.fetch(channel_name)

      expect(mapped_class_name).to eq("::#{service_class_name}")
      expect(mapped_class_name.constantize).to receive(:new).with(message: message).and_return(process_service)
      expect(process_service).to receive(:perform)

      described_class.perform_now(message.id)
    end

    it 'calls Facebook::SendOnFacebookService when its facebook message' do
      stub_request(:post, /graph.facebook.com/)
      facebook_channel = create(:channel_facebook_page)
      facebook_inbox = create(:inbox, channel: facebook_channel)
      message = create(:message, conversation: create(:conversation, inbox: facebook_inbox))
      allow(Facebook::SendOnFacebookService).to receive(:new).with(message: message).and_return(process_service)
      expect(Facebook::SendOnFacebookService).to receive(:new).with(message: message)
      expect(process_service).to receive(:perform)
      described_class.perform_now(message.id)
    end

    it 'calls ::Twitter::SendOnTwitterService when its twitter message' do
      twitter_channel = create(:channel_twitter_profile)
      twitter_inbox = create(:inbox, channel: twitter_channel)
      message = create(:message, conversation: create(:conversation, inbox: twitter_inbox))
      expect_mapped_service_to_perform(message, 'Twitter::SendOnTwitterService')
    end

    it 'calls ::Twilio::SendOnTwilioService when its twilio message' do
      twilio_channel = create(:channel_twilio_sms)
      message = create(:message, conversation: create(:conversation, inbox: twilio_channel.inbox))
      expect_mapped_service_to_perform(message, 'Twilio::SendOnTwilioService')
    end

    it 'calls ::Telegram::SendOnTelegramService when its telegram message' do
      telegram_channel = create(:channel_telegram)
      message = create(:message, conversation: create(:conversation, inbox: telegram_channel.inbox))
      expect_mapped_service_to_perform(message, 'Telegram::SendOnTelegramService')
    end

    it 'calls ::Line:SendOnLineService when its line message' do
      line_channel = create(:channel_line)
      message = create(:message, conversation: create(:conversation, inbox: line_channel.inbox))
      expect_mapped_service_to_perform(message, 'Line::SendOnLineService')
    end

    it 'calls ::Whatsapp:SendOnWhatsappService when its whatsapp message' do
      stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
      whatsapp_channel = create(:channel_whatsapp, sync_templates: false)
      message = create(:message, conversation: create(:conversation, inbox: whatsapp_channel.inbox))
      expect_mapped_service_to_perform(message, 'Whatsapp::SendOnWhatsappService')
    end

    it 'calls ::Sms::SendOnSmsService when its sms message' do
      sms_channel = create(:channel_sms)
      message = create(:message, conversation: create(:conversation, inbox: sms_channel.inbox))
      expect_mapped_service_to_perform(message, 'Sms::SendOnSmsService')
    end

    it 'calls ::Instagram::Direct::SendOnInstagramService when its instagram message' do
      instagram_channel = create(:channel_instagram)
      message = create(:message, conversation: create(:conversation, inbox: instagram_channel.inbox))
      expect_mapped_service_to_perform(message, 'Instagram::SendOnInstagramService')
    end

    it 'calls ::Instagram::Messenger::SendOnInstagramService when its an instagram_direct_message from facebook channel' do
      stub_request(:post, /graph.facebook.com/)
      facebook_channel = create(:channel_facebook_page)
      facebook_inbox = create(:inbox, channel: facebook_channel)
      conversation = create(:conversation,
                            inbox: facebook_inbox,
                            additional_attributes: { 'type' => 'instagram_direct_message' })
      message = create(:message, conversation: conversation)

      allow(Instagram::Messenger::SendOnInstagramService).to receive(:new).with(message: message).and_return(process_service)
      expect(Instagram::Messenger::SendOnInstagramService).to receive(:new).with(message: message)
      expect(process_service).to receive(:perform)
      described_class.perform_now(message.id)
    end

    it 'calls ::Email::SendOnEmailService when its email message' do
      email_channel = create(:channel_email)
      message = create(:message, conversation: create(:conversation, inbox: email_channel.inbox))
      expect_mapped_service_to_perform(message, 'Email::SendOnEmailService')
    end

    it 'calls ::Messages::SendEmailNotificationService when its webwidget message' do
      webwidget_channel = create(:channel_widget)
      message = create(:message, conversation: create(:conversation, inbox: webwidget_channel.inbox))
      expect_mapped_service_to_perform(message, 'Messages::SendEmailNotificationService')
    end

    it 'calls ::Messages::SendEmailNotificationService when its api channel message' do
      api_channel = create(:channel_api)
      message = create(:message, conversation: create(:conversation, inbox: api_channel.inbox))
      expect_mapped_service_to_perform(message, 'Messages::SendEmailNotificationService')
    end

    it 'calls ::Tiktok::SendOnTiktokService when its tiktok message' do
      tiktok_channel = create(:channel_tiktok)
      message = create(:message, conversation: create(:conversation, inbox: tiktok_channel.inbox))
      expect_mapped_service_to_perform(message, 'Tiktok::SendOnTiktokService')
    end
  end

  # Until this existed an exhausted job died in the dead set in silence, leaving the
  # bubble on "sent" with a clock next to it. Nobody watches the dead set, so the
  # exhaustion handler is the last chance to tell the agent it did not go out.
  describe 'when retries run out' do
    let(:message) { create(:message, message_type: :outgoing) }

    it 'marks the message failed with the reason' do
      described_class.fail_message(message.id, 'the provider never answered')

      expect(message.reload.status).to eq('failed')
      expect(message.external_error).to eq('the provider never answered')
    end

    it 'does not overwrite a reason already recorded on the message' do
      message.update_under_lock!(status: :failed, external_error: 'already recorded')

      described_class.fail_message(message.id, 'the later reason')

      expect(message.reload.external_error).to eq('already recorded')
    end

    it 'ignores a message that no longer exists' do
      expect { described_class.fail_message(-1, 'gone') }.not_to raise_error
    end

    # The idempotency lock clears in about the time a bounded send takes; the default
    # backoff burned all three retries well before that, so the conflict alone was enough
    # to kill the job every time.
    #
    # Asserted on the scheduled retry rather than on the handler list, because being
    # registered is not the same as being reached: retry_on is built on rescue_from,
    # which matches with reverse_each, so the broad Errors::Error handler shadows this
    # one unless it is declared first. A membership check passes either way.
    it 'gives a processing conflict its own, longer backoff' do
      whatsapp_channel = create(:channel_whatsapp, sync_templates: false, validate_provider_config: false)
      whatsapp_message = create(
        :message,
        message_type: :outgoing,
        conversation: create(:conversation, inbox: whatsapp_channel.inbox)
      )
      service = instance_double(Whatsapp::SendOnWhatsappService)
      allow(Whatsapp::SendOnWhatsappService).to receive(:new).and_return(service)
      allow(service).to receive(:perform)
        .and_raise(Whatsapp::Providers::WhatsappBaileysService::MessageAlreadyProcessingError)

      expect { described_class.perform_now(whatsapp_message.id) }
        .to have_enqueued_job(described_class)

      scheduled_in = enqueued_jobs.last[:at] - Time.zone.now.to_f
      expect(scheduled_in).to be_within(5).of(60)
    end
  end
end
