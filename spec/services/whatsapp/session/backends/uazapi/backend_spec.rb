require 'rails_helper'

RSpec.describe Whatsapp::Session::Backends::Uazapi::Backend do
  subject(:backend) { described_class.new(channel) }

  let(:channel) { create(:channel_whatsapp, provider: 'uazapi', validate_provider_config: false, sync_templates: false) }
  let(:model) { Whatsapp::Session::Model }
  let(:commands) { Whatsapp::Session::Model::Commands }
  let(:base) { 'https://uazapi.test' }
  let(:phone) { model::Address.phone('5541999990000') }

  def fixture(name)
    JSON.parse(Rails.root.join("spec/fixtures/whatsapp/session/uazapi/rest/#{name}.json").read)
  end

  def stub_uazapi(method, path, response = {}, status: 200)
    stub_request(method, "#{base}#{path}").to_return(
      status: status, body: response.to_json, headers: { 'Content-Type' => 'application/json' }
    )
  end

  before do
    # The contract examples call one method per declared capability, so every endpoint has
    # to answer something. Each example below overrides the one it is actually about.
    stub_request(:any, /uazapi\.test/).to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, 'https://example.test/file.jpg').to_return(status: 200, body: 'bytes',
                                                                  headers: { 'Content-Type' => 'image/jpeg' })
    stub_uazapi(:post, '/webhook', fixture('webhook_register'))
    stub_uazapi(:post, '/instance/connect', fixture('instance_connect_qr'))
    stub_uazapi(:get, '/instance/status', fixture('instance_status_connected'))
    stub_uazapi(:post, '/send/text', fixture('send_text'))
  end

  it_behaves_like 'a whatsapp session backend'

  describe 'the config it will accept' do
    it 'needs a URL and a token, and asks the provider for nothing' do
      expect(described_class.validate_config({})).to contain_exactly('base_url', 'token')
      expect(described_class.validate_config('base_url' => 'not a url', 'token' => 'x')).to eq(['base_url'])
      expect(described_class.validate_config('base_url' => base, 'token' => 'x')).to be_empty
    end
  end

  describe 'connecting' do
    # The webhook has to be up before the session is, or the messages that arrive while it
    # opens have nowhere to be delivered.
    it 'registers the webhook first, pointing at this inbox with its own secret' do
      backend.connect(commands::SessionConnect.new(pairing: 'qr'))

      expect(WebMock).to(have_requested(:post, "#{base}/webhook").with do |request|
        body = JSON.parse(request.body)
        body['url'].end_with?("/webhooks/whatsapp/session/uazapi/#{channel.id}/#{channel.provider_config['webhook_verify_token']}") &&
          body['excludeMessages'] == ['wasSentByApi'] && body['enabled'] == true
      end)
    end

    it 'answers with the QR the operator has to scan' do
      state = backend.connect(commands::SessionConnect.new(pairing: 'qr'))

      expect(state).to have_attributes(connection: 'connecting')
      expect(state.qr_data_url).to start_with('data:image/png;base64,')
    end

    # A number only goes on the connect when the operator asked for a pairing code:
    # sending one otherwise is what makes the provider skip the QR.
    it 'sends the phone only when pairing by code' do
      backend.connect(commands::SessionConnect.new(pairing: 'qr', phone: '5541999991111'))

      expect(WebMock).to(have_requested(:post, "#{base}/instance/connect").with { |request| request.body.exclude?('5541999991111') })
    end

    it 'sends the phone when pairing by code' do
      backend.connect(commands::SessionConnect.new(pairing: 'code', phone: '5541999991111'))

      expect(WebMock).to have_requested(:post, "#{base}/instance/connect")
        .with(body: hash_including('phone' => '5541999991111'))
    end
  end

  describe 'the connection state' do
    it 'reports the paired number when the session is open' do
      expect(backend.fetch_connection_state).to have_attributes(connection: 'open', phone_number: '553499990002')
    end

    context 'when the instance is disconnected' do
      before { stub_uazapi(:get, '/instance/status', fixture('instance_status_disconnected')) }

      it 'reports no number, because `owner` keeps the last one it saw' do
        expect(backend.fetch_connection_state).to have_attributes(connection: 'close', phone_number: nil)
      end
    end

    context 'when the phone logged the session out' do
      before { stub_uazapi(:get, '/instance/status', fixture('instance_status_disconnected_after_pairing')) }

      it 'says the pairing itself is gone' do
        expect(backend.fetch_connection_state).to have_attributes(connection: 'close', error: 'logged_out')
      end
    end

    context 'when the instance is waiting to be paired' do
      before { stub_uazapi(:get, '/instance/status', fixture('instance_status_connecting')) }

      it 'carries the code on screen' do
        expect(backend.fetch_connection_state).to have_attributes(connection: 'connecting', phone_number: nil)
        expect(backend.fetch_connection_state.qr_data_url).to be_present
      end
    end
  end

  # There is no unpair endpoint on this provider: `/instance/logout` answers 405.
  describe 'ending a session' do
    before { stub_uazapi(:post, '/instance/disconnect', fixture('instance_disconnect')) }

    it 'logs out by disconnecting' do
      backend.logout

      expect(WebMock).to have_requested(:post, "#{base}/instance/disconnect")
    end

    it 'withdraws the webhook before disconnecting when the inbox is torn down' do
      backend.delete_session

      expect(WebMock).to have_requested(:post, "#{base}/webhook").with(body: hash_including('enabled' => false))
      expect(WebMock).to have_requested(:post, "#{base}/instance/disconnect")
    end

    # The inbox is going away either way, and a provider that cannot be reached must not
    # be what keeps a conversion from finishing.
    it 'disconnects even when the webhook cannot be withdrawn' do
      stub_uazapi(:post, '/webhook', {}, status: 500)

      expect { backend.delete_session }.not_to raise_error
      expect(WebMock).to have_requested(:post, "#{base}/instance/disconnect")
    end
  end

  describe 'sending' do
    it 'carries the reserved id as the track id, since the provider assigns its own' do
      result = backend.send_message(
        commands::MessageSend.new(message_id: '3EB0RESERVED', to: phone, content: model::Content::Text.new(body: 'oi'),
                                  client_ref: '3EB0RESERVED')
      )

      expect(WebMock).to have_requested(:post, "#{base}/send/text")
        .with(body: hash_including('number' => '5541999990000', 'text' => 'oi', 'track_id' => '3EB0RESERVED'))
      expect(result.message_id).to eq('3EB00000000000000013')
    end

    it 'addresses a group by its full jid' do
      backend.send_message(
        commands::MessageSend.new(message_id: '3EB0AAAA', to: model::Address.group('120363040000000001'),
                                  content: model::Content::Text.new(body: 'oi'))
      )

      expect(WebMock).to have_requested(:post, "#{base}/send/text")
        .with(body: hash_including('number' => '120363040000000001@g.us'))
    end

    describe 'media' do
      let(:media) do
        model::Content::Media.new(kind: 'audio', mime: 'audio/ogg', voice_note: true, caption: nil,
                                  ref: model::MediaRef.url('https://chatwoot.test/audio.ogg'))
      end

      before { stub_uazapi(:post, '/send/media', fixture('send_media_image')) }

      # A voice note is its own type on WhatsApp; sent as `audio` it renders as a music
      # file instead of the recorded-voice bubble.
      it 'sends a voice note as a push-to-talk, with the url the provider fetches itself' do
        backend.send_message(commands::MessageSend.new(message_id: '3EB0AAAA', to: phone, content: media))

        expect(WebMock).to have_requested(:post, "#{base}/send/media")
          .with(body: hash_including('type' => 'ptt', 'file' => 'https://chatwoot.test/audio.ogg'))
      end
    end

    it 'refuses a content type it cannot send' do
      expect do
        backend.send_message(
          commands::MessageSend.new(message_id: '3EB0AAAA', to: phone,
                                    content: model::Content::Location.new(latitude: 1.0, longitude: 2.0))
        )
      end.to raise_error(Whatsapp::Session::Errors::InvalidPayload)
    end
  end

  # The provider answers an edit with a new message id pointing at the original. Storing
  # that id would rename the message the conversation already knows.
  describe 'editing' do
    before { stub_uazapi(:post, '/message/edit', fixture('message_edit')) }

    it 'keeps the original id' do
      result = backend.edit_message(
        commands::MessageEdit.new(target_id: '3EB0ORIGINAL', to: phone, content: model::Content::Text.new(body: 'nova'))
      )

      expect(WebMock).to have_requested(:post, "#{base}/message/edit")
        .with(body: hash_including('id' => '3EB0ORIGINAL', 'text' => 'nova'))
      expect(result.message_id).to eq('3EB0ORIGINAL')
    end
  end

  describe 'downloading media' do
    let(:command) do
      commands::MessageDownloadMedia.new(
        chat: phone, message_id: '3EB0AAAA',
        ref: model::MediaRef.new(kind: 'uazapi_message', id: '3EB0AAAA', mime: 'audio/ogg; codecs=opus')
      )
    end

    before do
      stub_uazapi(:post, '/message/download', fixture('message_download_ptt'))
      stub_request(:get, %r{https://free\.uazapi\.com/files/}).to_return(
        status: 200, body: 'bytes', headers: { 'Content-Type' => 'audio/mpeg' }
      )
    end

    # The URL a media message carries is the encrypted blob on WhatsApp's CDN, so the
    # bytes always take two hops. The provider transcodes on the second one, which is why
    # the mime it answers with wins over the one the message declared.
    it 'asks the provider to decrypt it and reports the type it actually got' do
      payload = backend.download_media(command)

      expect(WebMock).to have_requested(:post, "#{base}/message/download")
        .with(body: hash_including('id' => '3EB0AAAA', 'return_link' => true))
      expect(payload.mime).to eq('audio/mpeg')
    end

    it 'gives up when the provider has no file to hand over' do
      stub_uazapi(:post, '/message/download', { 'mimetype' => 'image/jpeg' })

      expect { backend.download_media(command) }.to raise_error(Whatsapp::Session::Errors::MediaUnavailable)
    end
  end

  describe 'the account limits' do
    before { stub_uazapi(:get, '/instance/wa_messages_limits', fixture('instance_wa_messages_limits')) }

    it 'answers in the shape the dashboard banner reads' do
      limits = backend.fetch_account_limits

      expect(limits['reachout_time_lock']).to eq('is_active' => false)
      expect(limits['new_chat_cap']).to include('total_quota' => 0, 'used_quota' => 0)
    end
  end

  describe 'checking numbers' do
    before { stub_uazapi(:post, '/chat/check', fixture('chat_check')) }

    it 'reports each number with the address WhatsApp knows it by' do
      checks = backend.check_numbers(commands::ContactCheck.new(phones: %w[553499990002 5500010000000]))

      expect(checks.first).to have_attributes(phone: '553499990002', exists: true)
      expect(checks.first.address).to eq(model::Address.lid('900000100000000'))
      expect(checks.last).to have_attributes(exists: false, address: nil)
    end
  end

  describe 'groups' do
    it 'reads a created group into the canonical snapshot' do
      stub_uazapi(:post, '/group/create', fixture('group_create'))

      info = backend.create_group(commands::GroupCreate.new(subject: 'captura chatwoot', participants: [phone]))

      expect(info.subject).to eq('captura chatwoot')
      expect(info.group).to eq(model::Address.group('120363000002000000'))
    end

    it 'changes a roster by naming the action and the people' do
      stub_uazapi(:post, '/group/updateParticipants', fixture('group_participants_remove'))

      backend.update_group_participants(
        commands::GroupParticipantsUpdate.new(group: model::Address.group('120363000002000000'), participants: [phone],
                                              action: 'remove')
      )

      expect(WebMock).to have_requested(:post, "#{base}/group/updateParticipants")
        .with(body: hash_including('groupjid' => '120363000002000000@g.us', 'action' => 'remove',
                                   'participants' => ['5541999990000']))
    end

    # The build we captured does not serve `/group/info`, and losing the capability over
    # that would take the whole group sync with it. The listing carries the same snapshot.
    context 'when the provider does not serve /group/info' do
      before do
        stub_uazapi(:post, '/group/info', { 'message' => 'Method Not Allowed.' }, status: 405)
        stub_request(:get, "#{base}/group/list").with(query: { force: true })
                                                .to_return(status: 200, body: fixture('group_list_2').to_json,
                                                           headers: { 'Content-Type' => 'application/json' })
      end

      it 'falls back to finding it in the listing' do
        info = backend.group_info(commands::GroupInfo.new(group: model::Address.group('120363000002000000')))

        expect(info.subject).to eq('captura chatwoot')
      end

      it 'says so when the listing does not have it either' do
        expect do
          backend.group_info(commands::GroupInfo.new(group: model::Address.group('120363000009999999')))
        end.to raise_error(Whatsapp::Session::Errors::SessionNotFound)
      end
    end
  end

  describe 'the small commands' do
    it 'reacts with the emoji, pointing at the message it annotates' do
      stub_uazapi(:post, '/message/react', fixture('message_react'))

      backend.react_message(commands::MessageReact.new(to: phone, target_id: '3EB0TARGET', emoji: '👍'))

      expect(WebMock).to have_requested(:post, "#{base}/message/react")
        .with(body: hash_including('number' => '5541999990000', 'id' => '3EB0TARGET', 'text' => '👍'))
    end

    it 'marks a batch of messages read in one call' do
      stub_uazapi(:post, '/message/markread', fixture('mark_read'))

      backend.mark_read(commands::MessageMarkRead.new(chat: phone, message_ids: %w[3EB0AAAA 3EB0BBBB]))

      expect(WebMock).to have_requested(:post, "#{base}/message/markread")
        .with(body: hash_including('id' => %w[3EB0AAAA 3EB0BBBB]))
    end

    it 'sends a typing indicator that expires on its own' do
      stub_uazapi(:post, '/message/presence', fixture('presence_composing'))

      backend.send_chat_presence(commands::ChatPresence.new(chat: phone, state: 'composing'))

      expect(WebMock).to have_requested(:post, "#{base}/message/presence")
        .with(body: hash_including('presence' => 'composing'))
    end

    # `imagePreview` is the small copy; the full one is what an avatar sync wants.
    it 'reads a profile picture off the chat details' do
      stub_uazapi(:post, '/chat/details', fixture('chat_details'))

      url = backend.profile_picture_url(commands::ContactProfilePicture.new(party: phone, preview: false))

      expect(url).to start_with('https://pps.whatsapp.net/')
    end
  end

  # `/group/invitelink` answers 405 on this provider, and the group snapshot carries no
  # code either, so the capability is not declared and the endpoint is never called.
  it 'refuses to hand out an invite code' do
    expect do
      backend.group_invite_code(commands::GroupInviteGet.new(group: model::Address.group('120363040000000001')))
    end.to raise_error(Whatsapp::Session::Errors::NotSupported)
  end
end
