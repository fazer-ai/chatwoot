require 'rails_helper'

describe Whatsapp::WebhookSetupService do
  let(:channel) do
    create(:channel_whatsapp,
           phone_number: '+1234567890',
           provider_config: {
             'phone_number_id' => '123456789',
             'webhook_verify_token' => 'test_verify_token',
             'source' => 'embedded_signup'
           },
           provider: 'whatsapp_cloud',
           sync_templates: false,
           validate_provider_config: false)
  end
  let(:waba_id) { 'test_waba_id' }
  let(:access_token) { 'test_access_token' }
  let(:service) { described_class.new(channel, waba_id, access_token) }
  let(:api_client) { instance_double(Whatsapp::FacebookApiClient) }
  let(:health_service) { instance_double(Whatsapp::HealthService) }

  before do
    # Stub webhook teardown to prevent HTTP calls during cleanup
    stub_request(:delete, /graph.facebook.com/).to_return(status: 200, body: '{}', headers: {})

    # Clean up any existing channels to avoid phone number conflicts
    Channel::Whatsapp.destroy_all
    allow(Whatsapp::FacebookApiClient).to receive(:new).and_return(api_client)
    allow(Whatsapp::HealthService).to receive(:new).and_return(health_service)

    # Default stubs for the code verification read and the health service
    allow(api_client).to receive(:phone_number_code_verification_status).and_return('NOT_VERIFIED')
    allow(health_service).to receive(:fetch_health_status).and_return({
                                                                        platform_type: 'APPLICABLE',
                                                                        throughput: { level: 'APPLICABLE' }
                                                                      })
  end

  describe '#perform' do
    context 'when phone number is NOT verified (should register)' do
      before do
        allow(api_client).to receive(:phone_number_code_verification_status).with('123456789').and_return('NOT_VERIFIED')
        allow(SecureRandom).to receive(:random_number).with(900_000).and_return(123_456)
        allow(api_client).to receive(:register_phone_number).with('123456789', 223_456)
        allow(api_client).to receive(:subscribe_phone_number_webhook)
          .with(waba_id, '123456789', anything, 'test_verify_token',
                subscribed_fields: %w[messages smb_message_echoes]).and_return({ 'success' => true })
        allow(channel).to receive(:save!)
      end

      it 'registers the phone number and sets up webhook' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).to receive(:register_phone_number).with('123456789', 223_456)
          expect(api_client).to receive(:subscribe_phone_number_webhook)
            .with(waba_id, '123456789', 'https://app.chatwoot.com/webhooks/whatsapp/+1234567890', 'test_verify_token',
                  subscribed_fields: %w[messages smb_message_echoes])
          service.perform
        end
      end
    end

    context 'when phone number IS verified AND fully provisioned (should NOT register)' do
      before do
        allow(api_client).to receive(:phone_number_code_verification_status).with('123456789').and_return('VERIFIED')
        allow(health_service).to receive(:fetch_health_status).and_return({
                                                                            platform_type: 'APPLICABLE',
                                                                            throughput: { level: 'APPLICABLE' }
                                                                          })
        allow(api_client).to receive(:subscribe_phone_number_webhook)
          .with(waba_id, '123456789', anything, 'test_verify_token',
                subscribed_fields: %w[messages smb_message_echoes]).and_return({ 'success' => true })
      end

      it 'does NOT register phone, but sets up webhook' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).not_to receive(:register_phone_number)
          expect(api_client).to receive(:subscribe_phone_number_webhook)
            .with(waba_id, '123456789', 'https://app.chatwoot.com/webhooks/whatsapp/+1234567890', 'test_verify_token',
                  subscribed_fields: %w[messages smb_message_echoes])
          service.perform
        end
      end
    end

    context 'when phone number IS verified BUT needs registration (pending provisioning)' do
      before do
        allow(api_client).to receive(:phone_number_code_verification_status).with('123456789').and_return('VERIFIED')
        allow(health_service).to receive(:fetch_health_status).and_return({
                                                                            platform_type: 'NOT_APPLICABLE',
                                                                            throughput: { level: 'APPLICABLE' }
                                                                          })
        allow(SecureRandom).to receive(:random_number).with(900_000).and_return(123_456)
        allow(api_client).to receive(:register_phone_number).with('123456789', 223_456)
        allow(api_client).to receive(:subscribe_phone_number_webhook)
          .with(waba_id, '123456789', anything, 'test_verify_token',
                subscribed_fields: %w[messages smb_message_echoes]).and_return({ 'success' => true })
        allow(channel).to receive(:save!)
      end

      it 'registers the phone number due to pending provisioning state' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).to receive(:register_phone_number).with('123456789', 223_456)
          expect(api_client).to receive(:subscribe_phone_number_webhook)
            .with(waba_id, '123456789', 'https://app.chatwoot.com/webhooks/whatsapp/+1234567890', 'test_verify_token',
                  subscribed_fields: %w[messages smb_message_echoes])
          service.perform
        end
      end
    end

    context 'when the pending state comes only from throughput, in the shape HealthService produces' do
      # HealthService keeps Meta's `throughput` object verbatim, so its keys are strings, and it
      # derives `:throughput_level` alongside. A spec that stubs `throughput: { level: ... }` with
      # symbols is testing a payload the app never sees.
      before do
        allow(api_client).to receive(:phone_number_code_verification_status).with('123456789').and_return('VERIFIED')
        allow(health_service).to receive(:fetch_health_status).and_return({
                                                                            platform_type: 'APPLICABLE',
                                                                            throughput: { 'level' => 'NOT_APPLICABLE' },
                                                                            throughput_level: 'NOT_APPLICABLE'
                                                                          })
        allow(SecureRandom).to receive(:random_number).with(900_000).and_return(123_456)
        allow(api_client).to receive(:register_phone_number)
        allow(api_client).to receive(:subscribe_phone_number_webhook).and_return({ 'success' => true })
        allow(channel).to receive(:save!)
      end

      it 'registers the number' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).to receive(:register_phone_number).with('123456789', 223_456)
          service.perform
        end
      end

      it 'registers it on the unknown-verification path too, which is where it now matters' do
        # This is the path the change created: an unread verification used to register regardless,
        # and now it defers to health. If health misses the throughput half, the number is silently
        # left unregistered.
        allow(api_client).to receive(:phone_number_code_verification_status).with('123456789').and_raise('API down')

        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).to receive(:register_phone_number).with('123456789', 223_456)
          service.perform
        end
      end
    end

    context 'when phone number needs registration due to throughput level' do
      before do
        allow(api_client).to receive(:phone_number_code_verification_status).with('123456789').and_return('VERIFIED')
        allow(health_service).to receive(:fetch_health_status).and_return({
                                                                            platform_type: 'APPLICABLE',
                                                                            throughput: { 'level' => 'NOT_APPLICABLE' },
                                                                            throughput_level: 'NOT_APPLICABLE'
                                                                          })
        allow(SecureRandom).to receive(:random_number).with(900_000).and_return(123_456)
        allow(api_client).to receive(:register_phone_number).with('123456789', 223_456)
        allow(api_client).to receive(:subscribe_phone_number_webhook)
          .with(waba_id, '123456789', anything, 'test_verify_token',
                subscribed_fields: %w[messages smb_message_echoes]).and_return({ 'success' => true })
        allow(channel).to receive(:save!)
      end

      it 'registers the phone number due to throughput not applicable' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).to receive(:register_phone_number).with('123456789', 223_456)
          expect(api_client).to receive(:subscribe_phone_number_webhook)
            .with(waba_id, '123456789', 'https://app.chatwoot.com/webhooks/whatsapp/+1234567890', 'test_verify_token',
                  subscribed_fields: %w[messages smb_message_echoes])
          service.perform
        end
      end
    end

    # This context used to assert the opposite, that a failed read registers the number, and it was
    # green: the behaviour was written down as intended rather than arrived at by accident. #590 is
    # the argument that it should not be, and the flip is the whole point of the change, so the
    # example is rewritten here rather than deleted.
    context 'when the code verification read does not come back' do
      before do
        allow(api_client).to receive(:phone_number_code_verification_status).with('123456789').and_raise('API down')
        allow(health_service).to receive(:fetch_health_status).and_return({
                                                                            platform_type: 'APPLICABLE',
                                                                            throughput: { level: 'APPLICABLE' }
                                                                          })
        allow(api_client).to receive(:register_phone_number)
        allow(api_client).to receive(:subscribe_phone_number_webhook).and_return({ 'success' => true })
        allow(channel).to receive(:save!)
      end

      it 'does not register the number, because a read that did not answer is not a "no"' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).not_to receive(:register_phone_number)
          expect(api_client).to receive(:subscribe_phone_number_webhook)
          expect { service.perform }.not_to raise_error
        end
      end

      it 'still asks health, so the number is registered when health names the pending state' do
        # The old `||` short-circuited here: a read that failed counted as "not verified" and the
        # health call never happened. Now the second axis gets to answer on its own.
        allow(health_service).to receive(:fetch_health_status).and_return({
                                                                            platform_type: 'NOT_APPLICABLE',
                                                                            throughput: { level: 'APPLICABLE' }
                                                                          })
        allow(SecureRandom).to receive(:random_number).with(900_000).and_return(123_456)

        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(health_service).to receive(:fetch_health_status)
          expect(api_client).to receive(:register_phone_number).with('123456789', 223_456)
          service.perform
        end
      end

      # The decision has two outcomes, so `:unknown` and `:verified` produce the same one and no
      # mutation of the decision can be caught here. This line is the whole surface of the third
      # state: without it asserted, a cleanup can put the app back in a two-state world where "could
      # not tell" is indistinguishable from "verified", and nothing turns red.
      it 'says the read did not answer, which is the only place that state is visible' do
        allow(Rails.logger).to receive(:error)

        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          service.perform
        end

        expect(Rails.logger).to have_received(:error)
          .with('[WHATSAPP] Could not read the code verification status for 123456789; ' \
                'not deciding registration from it: API down')
      end

      it 'does not raise, because the caller turns any raise into a reauthorization prompt' do
        # Channel::Whatsapp#setup_webhooks rescues everything out of #perform and calls
        # prompt_reauthorization!, and WhatsappEventsJob then discards every inbound webhook for
        # the channel. Answering "could not tell" by raising would be worse than the bug (#568).
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect { service.perform }.not_to raise_error
        end
      end
    end

    context 'when the code verification read answers an empty value' do
      # Absent, null and empty string are the same fact: the read did not answer the question. The
      # client hands them over verbatim now, so it is here that they have to mean the same thing.
      %w[nil empty].each do |shape|
        it "treats #{shape} as an answer that answers nothing" do
          allow(api_client).to receive(:phone_number_code_verification_status)
            .with('123456789').and_return(shape == 'nil' ? nil : '')
          allow(health_service).to receive(:fetch_health_status).and_return({
                                                                              platform_type: 'APPLICABLE',
                                                                              throughput: { level: 'APPLICABLE' }
                                                                            })
          allow(api_client).to receive(:register_phone_number)
          allow(api_client).to receive(:subscribe_phone_number_webhook).and_return({ 'success' => true })

          with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
            expect(api_client).not_to receive(:register_phone_number)
            service.perform
          end
        end

        it "says so, because #{shape} decides nothing and the log is where that shows" do
          allow(api_client).to receive(:phone_number_code_verification_status)
            .with('123456789').and_return(shape == 'nil' ? nil : '')
          allow(health_service).to receive(:fetch_health_status).and_return({
                                                                              platform_type: 'APPLICABLE',
                                                                              throughput: { level: 'APPLICABLE' }
                                                                            })
          allow(api_client).to receive(:subscribe_phone_number_webhook).and_return({ 'success' => true })
          allow(Rails.logger).to receive(:error)

          with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
            service.perform
          end

          expect(Rails.logger).to have_received(:error)
            .with('[WHATSAPP] Phone number 123456789 answered no code verification status; ' \
                  'not deciding registration from it')
        end
      end
    end

    context 'when the code verification read answers something that is not VERIFIED' do
      # EXPIRED is a documented Meta value and is a definite "no", not a silence.
      %w[NOT_VERIFIED PENDING EXPIRED].each do |status|
        it "registers on #{status}, because Meta answered" do
          allow(api_client).to receive(:phone_number_code_verification_status).with('123456789').and_return(status)
          allow(SecureRandom).to receive(:random_number).with(900_000).and_return(123_456)
          allow(api_client).to receive(:register_phone_number)
          allow(api_client).to receive(:subscribe_phone_number_webhook).and_return({ 'success' => true })

          with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
            expect(api_client).to receive(:register_phone_number).with('123456789', 223_456)
            service.perform
          end
        end
      end
    end

    context 'when the code verification read answers without the field' do
      before do
        # A perfectly good 200 that does not carry `code_verification_status`. This never reached a
        # rescue: it turned into `false` inside the client, one layer below where anyone was looking.
        allow(api_client).to receive(:phone_number_code_verification_status).with('123456789').and_return(nil)
        allow(health_service).to receive(:fetch_health_status).and_return({
                                                                            platform_type: 'APPLICABLE',
                                                                            throughput: { level: 'APPLICABLE' }
                                                                          })
        allow(api_client).to receive(:register_phone_number)
        allow(api_client).to receive(:subscribe_phone_number_webhook).and_return({ 'success' => true })
        allow(channel).to receive(:save!)
      end

      it 'does not register the number either, because an answer without the field answers nothing' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).not_to receive(:register_phone_number)
          service.perform
        end
      end
    end

    context 'when health service raises error' do
      before do
        allow(api_client).to receive(:phone_number_code_verification_status).with('123456789').and_return('VERIFIED')
        allow(health_service).to receive(:fetch_health_status).and_raise('Health API down')
        allow(api_client).to receive(:subscribe_phone_number_webhook).and_return({ 'success' => true })
      end

      it 'does not register phone (conservative approach) and proceeds with webhook setup' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).not_to receive(:register_phone_number)
          expect(api_client).to receive(:subscribe_phone_number_webhook)
          expect { service.perform }.not_to raise_error
        end
      end

      # Same hole on the other axis: `:unknown` and `:not_pending` lead to the same decision, so the
      # line is the only thing that separates "health said no" from "health did not say".
      it 'says the health read did not answer' do
        allow(Rails.logger).to receive(:error)

        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          service.perform
        end

        expect(Rails.logger).to have_received(:error)
          .with('[WHATSAPP] Could not read the health status; not deciding registration from it: Health API down')
      end
    end

    context 'when phone registration fails (not blocking)' do
      before do
        allow(api_client).to receive(:phone_number_code_verification_status).with('123456789').and_return('NOT_VERIFIED')
        allow(SecureRandom).to receive(:random_number).with(900_000).and_return(123_456)
        allow(api_client).to receive(:register_phone_number).and_raise('Registration failed')
        allow(api_client).to receive(:subscribe_phone_number_webhook).and_return({ 'success' => true })
        allow(channel).to receive(:save!)
      end

      it 'continues with webhook setup even if registration fails' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).to receive(:register_phone_number)
          expect(api_client).to receive(:subscribe_phone_number_webhook)
          expect { service.perform }.not_to raise_error
        end
      end
    end

    context 'when the registration write does not come back' do
      let(:provider_config) { super().merge('verification_pin' => nil) }

      before do
        allow(api_client).to receive(:phone_number_code_verification_status).with('123456789').and_return('NOT_VERIFIED')
        allow(SecureRandom).to receive(:random_number).with(900_000).and_return(123_456)
        allow(api_client).to receive(:register_phone_number).and_raise(Net::ReadTimeout)
        allow(api_client).to receive(:subscribe_phone_number_webhook).and_return({ 'success' => true })
      end

      it 'keeps the PIN it sent, because Meta may be holding that one' do
        # The PIN used to be stored only after the call returned, so an attempt whose outcome nobody
        # saw left nothing behind and the next one drew a different number. Then the app could not
        # name what might already be valid on Meta's side (#590).
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          service.perform
        end

        expect(channel.reload.provider_config['verification_pin']).to eq(223_456)
      end

      it 'leaves the PIN unconfirmed, so the three states stay readable' do
        # No PIN means Meta holds none. A confirmed PIN means Meta holds this one. An unconfirmed
        # PIN means nobody knows, and that is the state this endpoint could not write down before.
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          service.perform
        end

        config = channel.reload.provider_config
        expect(config['verification_pin']).to eq(223_456)
        expect(config).not_to have_key('verification_pin_confirmed')
      end

      it 'keeps the PIN even when Meta refused, because a refusal establishes nothing about it' do
        # A 5xx, a rate limit, a body this code could not parse and a failure to save the
        # confirmation after a registration Meta ACCEPTED all arrive here as the same exception.
        # Dropping the PIN on any of them loses one that may be live and sends a different one next
        # time, which is the disagreement this change exists to prevent.
        allow(api_client).to receive(:register_phone_number).and_raise('Phone registration failed: {"error":"bad pin"}')

        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          service.perform
        end

        expect(channel.reload.provider_config['verification_pin']).to eq(223_456)
      end

      it 'keeps a PIN Meta already confirmed when saving the confirmation itself fails' do
        # The worst case of dropping on failure: the registration landed, and the exception comes
        # from the write that records it.
        allow(api_client).to receive(:register_phone_number).and_return({ 'success' => true })
        allow(channel).to receive(:save!).with(validate: false).and_call_original
        call = 0
        allow(channel).to receive(:save!).with(validate: false) do
          call += 1
          raise ActiveRecord::RecordInvalid if call > 1

          true
        end

        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect { service.perform }.not_to raise_error
        end
      end

      it 'confirms the PIN when the call came back, because then Meta holds this one' do
        allow(api_client).to receive(:register_phone_number).and_return({ 'success' => true })

        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          service.perform
        end

        config = channel.reload.provider_config
        expect(config['verification_pin']).to eq(223_456)
        expect(config['verification_pin_confirmed']).to be(true)
      end

      it 'says the outcome is unknown, not that Meta refused' do
        # A refusal and a silence used to share this line verbatim. One is something the app knows.
        allow(Rails.logger).to receive(:warn)

        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          service.perform
        end

        expect(Rails.logger).to have_received(:warn).with(/outcome unknown/)
        expect(Rails.logger).not_to have_received(:warn).with(/refused/)
      end

      it 'never puts the PIN in the log, because it is a credential' do
        # Direct interpolation into the logger bypasses Rails parameter filtering, and on a timeout
        # this is very likely the PIN Meta is holding.
        allow(Rails.logger).to receive(:warn)

        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          service.perform
        end

        expect(Rails.logger).not_to have_received(:warn).with(/223456|223_456/)
      end

      it 'writes the PIN without re-validating the credentials against Meta' do
        # A plain save! runs validate_provider_config, which is another Graph call, on the exact
        # path where Meta is already misbehaving. If that call failed, save! would raise, the rescue
        # around the registration would swallow it, and the POST /register would never leave.
        allow(channel).to receive(:save!)

        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          service.perform
        end

        expect(channel).to have_received(:save!).with(validate: false)
      end

      it 'still sends the registration when the channel validation would have failed' do
        allow(channel).to receive(:save!).with(validate: false).and_return(true)

        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).to receive(:register_phone_number).with('123456789', 223_456)
          service.perform
        end
      end

      it 'says Meta refused when Meta actually answered' do
        allow(api_client).to receive(:register_phone_number).and_raise('Phone registration failed: {"error":"bad pin"}')
        allow(Rails.logger).to receive(:warn)

        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          service.perform
        end

        expect(Rails.logger).to have_received(:warn).with(/refused/)
        expect(Rails.logger).not_to have_received(:warn).with(/outcome unknown/)
      end
    end

    context 'when webhook setup fails (should raise)' do
      before do
        allow(api_client).to receive(:phone_number_code_verification_status).with('123456789').and_return('NOT_VERIFIED')
        allow(SecureRandom).to receive(:random_number).with(900_000).and_return(123_456)
        allow(api_client).to receive(:register_phone_number)
        allow(api_client).to receive(:subscribe_phone_number_webhook).and_raise('Webhook failed')
      end

      it 'raises an error' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).to receive(:register_phone_number)
          expect(api_client).to receive(:subscribe_phone_number_webhook)
          expect { service.perform }.to raise_error(/Webhook setup failed/)
        end
      end
    end

    context 'when required parameters are missing' do
      it 'raises error when channel is nil' do
        service_invalid = described_class.new(nil, waba_id, access_token)
        expect { service_invalid.perform }.to raise_error(ArgumentError, 'Channel is required')
      end

      it 'raises error when waba_id is blank' do
        service_invalid = described_class.new(channel, '', access_token)
        expect { service_invalid.perform }.to raise_error(ArgumentError, 'WABA ID is required')
      end

      it 'raises error when access_token is blank' do
        service_invalid = described_class.new(channel, waba_id, '')
        expect { service_invalid.perform }.to raise_error(ArgumentError, 'Access token is required')
      end
    end

    context 'when PIN already exists' do
      before do
        channel.provider_config['verification_pin'] = 123_456
        allow(api_client).to receive(:phone_number_code_verification_status).with('123456789').and_return('NOT_VERIFIED')
        allow(api_client).to receive(:register_phone_number)
        allow(api_client).to receive(:subscribe_phone_number_webhook).and_return({ 'success' => true })
        allow(channel).to receive(:save!)
      end

      it 'reuses existing PIN' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).to receive(:register_phone_number).with('123456789', 123_456)
          expect(SecureRandom).not_to receive(:random_number)
          service.perform
        end
      end

      it 'reuses it even when it was never confirmed, which is the whole reason to keep it' do
        # An unconfirmed PIN is the one a write left behind when nobody saw its outcome. Meta may be
        # holding exactly that number, so the retry has to send the same one; drawing a new one is
        # how the app used to guarantee it could never agree with Meta again (#590).
        channel.provider_config.delete('verification_pin_confirmed')

        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).to receive(:register_phone_number).with('123456789', 123_456)
          expect(SecureRandom).not_to receive(:random_number)
          service.perform
        end
      end

      it 'draws a new one after a refusal, because then the old one is not held anywhere' do
        channel.provider_config.delete('verification_pin')
        allow(SecureRandom).to receive(:random_number).with(900_000).and_return(123_456)

        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).to receive(:register_phone_number).with('123456789', 223_456)
          service.perform
        end
      end
    end

    context 'when webhook setup fails and should trigger reauthorization' do
      before do
        allow(api_client).to receive(:phone_number_code_verification_status).with('123456789').and_return('VERIFIED')
        allow(api_client).to receive(:subscribe_phone_number_webhook).and_raise('Invalid access token')
      end

      it 'raises error with webhook setup failure message' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect { service.perform }.to raise_error(/Webhook setup failed: Invalid access token/)
        end
      end

      it 'logs the webhook setup failure' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(Rails.logger).to receive(:error).with('[WHATSAPP] Webhook setup failed: Invalid access token')
          expect { service.perform }.to raise_error(/Webhook setup failed/)
        end
      end
    end

    context 'when used during reauthorization flow' do
      let(:existing_channel) do
        create(:channel_whatsapp,
               phone_number: '+1234567890',
               provider_config: {
                 'phone_number_id' => '123456789',
                 'webhook_verify_token' => 'existing_verify_token',
                 'business_id' => 'existing_business_id',
                 'waba_id' => 'existing_waba_id',
                 'source' => 'embedded_signup'
               },
               provider: 'whatsapp_cloud',
               sync_templates: false,
               validate_provider_config: false)
      end
      let(:new_access_token) { 'new_access_token' }
      let(:service_reauth) { described_class.new(existing_channel, waba_id, new_access_token) }

      before do
        allow(api_client).to receive(:phone_number_code_verification_status).with('123456789').and_return('VERIFIED')
        allow(health_service).to receive(:fetch_health_status).and_return({
                                                                            platform_type: 'APPLICABLE',
                                                                            throughput: { level: 'APPLICABLE' }
                                                                          })
        allow(api_client).to receive(:subscribe_phone_number_webhook)
          .with(waba_id, '123456789', anything, 'existing_verify_token',
                subscribed_fields: %w[messages smb_message_echoes]).and_return({ 'success' => true })
      end

      it 'successfully reauthorizes with new access token' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).not_to receive(:register_phone_number)
          expect(api_client).to receive(:subscribe_phone_number_webhook)
            .with(waba_id, '123456789', 'https://app.chatwoot.com/webhooks/whatsapp/+1234567890', 'existing_verify_token',
                  subscribed_fields: %w[messages smb_message_echoes])
          service_reauth.perform
        end
      end

      it 'uses the existing webhook verify token during reauthorization' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(api_client).to receive(:subscribe_phone_number_webhook)
            .with(waba_id, '123456789', anything, 'existing_verify_token',
                  subscribed_fields: %w[messages smb_message_echoes])
          service_reauth.perform
        end
      end
    end

    context 'when webhook setup is successful in creation flow' do
      before do
        allow(api_client).to receive(:phone_number_code_verification_status).with('123456789').and_return('VERIFIED')
        allow(health_service).to receive(:fetch_health_status).and_return({
                                                                            platform_type: 'APPLICABLE',
                                                                            throughput: { level: 'APPLICABLE' }
                                                                          })
        allow(api_client).to receive(:subscribe_phone_number_webhook)
          .with(waba_id, '123456789', anything, 'test_verify_token',
                subscribed_fields: %w[messages smb_message_echoes]).and_return({ 'success' => true })
      end

      it 'completes successfully without errors' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect { service.perform }.not_to raise_error
        end
      end

      it 'does not log any errors' do
        with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
          expect(Rails.logger).not_to receive(:error)
          service.perform
        end
      end
    end
  end
end
