require 'rails_helper'

RSpec.describe Whatsapp::Session::Backends::Connector::Backend do
  subject(:backend) { described_class.new(channel) }

  let(:channel) do
    create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false)
  end
  let(:session_id) { channel.provider_config['session_id'] }
  let(:client) { instance_double(Whatsapp::Connector::Client) }
  let(:model) { Whatsapp::Session::Model }

  # What the connector answers, per command type. Anything not listed answers nil, which
  # is enough for the commands whose result is only "it worked".
  let(:results) do
    {
      'session.connect' => { 'connection' => 'connecting', 'qr_data_url' => 'data:image/png;base64,AAA' },
      'session.status' => { 'connection' => 'open', 'reachout_time_lock' => { 'status' => 'UNLOCKED' } },
      'message.send' => { 'message_id' => '3EB0AAAA', 'timestamp' => 1_755_440_000_123 },
      'message.edit' => { 'message_id' => '3EB0BBBB', 'timestamp' => 1_755_440_000_123 },
      'message.react' => { 'message_id' => '3EB0CCCC', 'timestamp' => 1_755_440_000_123 },
      'message.download_media' => { 'kind' => 'url', 'url' => 'https://connector.test/media/abc', 'mime' => 'image/jpeg' },
      'contact.check' => [{ 'phone' => '5541999990000', 'exists' => true, 'address' => { 'kind' => 'phone', 'id' => '5541999990000' } }],
      'contact.profile_picture' => { 'url' => 'https://connector.test/avatar.jpg' },
      'group.create' => { 'group' => { 'kind' => 'group', 'id' => '120363040000000001' }, 'subject' => 'Equipe' },
      'group.info' => { 'group' => { 'kind' => 'group', 'id' => '120363040000000001' }, 'subject' => 'Equipe' },
      'group.invite.get' => { 'code' => 'FAKEINVITE0001' },
      'group.participants.update' => [{ 'address' => { 'kind' => 'phone', 'id' => '5541999990000' }, 'status' => 'success' }],
      'group.join_requests.list' => []
    }
  end

  before do
    allow(Whatsapp::Connector::Client).to receive(:new).with(session_id).and_return(client)
    allow(client).to receive(:publish).and_return('cmd-0001')
    # A real connector echoes back the id the caller reserved, which is what makes the
    # provider echo of the message recognizable.
    allow(client).to receive(:call) do |command, **|
      result = results[command.class.wire_type]
      result.is_a?(Hash) && result.key?('message_id') ? result.merge('message_id' => command.message_id) : result
    end
    allow(client).to receive(:media_token).with(anything).and_return('media-token')
    allow(Down).to receive(:download).and_return(
      StringIO.new('bytes').tap do |io|
        io.define_singleton_method(:content_type) { 'image/jpeg' }
        io.define_singleton_method(:original_filename) { 'photo.jpg' }
      end
    )
  end

  it_behaves_like 'a whatsapp session backend'

  it 'declares exactly what the registry advertises for the provider' do
    expect(described_class.capabilities).to eq(Whatsapp::Session::Registry.descriptor('native').capabilities)
  end

  it 'refuses to work without the session id the inbox should have generated' do
    channel.update_columns(provider_config: {}) # rubocop:disable Rails/SkipsModelValidations

    expect { described_class.new(channel).logout }.to raise_error(Whatsapp::Session::Errors::InvalidConfig)
  end

  it 'turns the connect reply into the connection state the inbox stores' do
    state = backend.connect(model::Commands::SessionConnect.new(pairing: 'qr'))

    expect(state).to be_connecting
    expect(state.qr_data_url).to be_present
  end

  it 'sends a message under an idempotency key built from its reserved id' do
    expect(client).to receive(:call).with(anything, idempotency_key: 'msg:3EB0AAAA').and_return(results['message.send'])

    result = backend.send_message(
      model::Commands::MessageSend.new(message_id: '3EB0AAAA', to: model::Address.phone('5541999990000'),
                                       content: model::Content::Text.new(body: 'oi'))
    )

    expect(result.message_id).to eq('3EB0AAAA')
  end

  it 'reads the account limits off the session status' do
    expect(backend.fetch_account_limits).to eq({ 'reachout_time_lock' => { 'status' => 'UNLOCKED' } })
  end

  it 'downloads media straight from the URL the event carried' do
    payload = backend.download_media(download_command(model::MediaRef.url('https://connector.test/media/abc', mime: 'image/jpeg')))

    expect(client).not_to have_received(:call)
    expect(Down).to have_received(:download).with(
      'https://connector.test/media/abc', hash_including(headers: hash_including('Authorization' => 'Bearer media-token'))
    )
    expect(payload.mime).to eq('image/jpeg')
  end

  it 'asks the connector to fetch the bytes again when the ref carries no URL' do
    backend.download_media(download_command(model::MediaRef.new(kind: 'connector_blob', id: 'abc')))

    expect(Down).to have_received(:download).with('https://connector.test/media/abc', anything)
  end

  # The connector drops its blobs on a TTL and an LRU quota, so a URL handed out with the
  # event is routinely dead by the time the download job runs. Treating that as terminal
  # marked the message unsupported while the bytes were still one command away.
  it 'asks again for a ref that has already lapsed' do
    lapsed = model::MediaRef.new(kind: 'connector_blob', id: 'abc', url: 'https://connector.test/media/stale',
                                 expires_at: 1.hour.ago.to_i * 1000)

    backend.download_media(download_command(lapsed))

    expect(Down).not_to have_received(:download).with('https://connector.test/media/stale', anything)
    expect(Down).to have_received(:download).with('https://connector.test/media/abc', anything)
  end

  # A refused request is an operational problem, not a missing file, and the two lead to
  # opposite outcomes: the job retries a refusal, while media that is gone marks the
  # message unsupported and never comes back.
  it 'tells a refused media request apart from media that is gone' do
    response = instance_double(Net::HTTPForbidden, code: '403')
    allow(Down).to receive(:download).and_raise(Down::ClientError.new('forbidden', response))

    expect { backend.download_media(download_command(model::MediaRef.url('https://connector.test/media/abc'))) }
      .to raise_error(Whatsapp::Session::Errors::Unauthorized)
  end

  # A blob URL names the instance that downloaded it, and that instance can be replaced
  # before the download job runs. Retrying the dead URL forever left the message without
  # its attachment; asking again reaches whoever holds the session now.
  it 'asks again when the instance serving the blob is no longer there' do
    allow(Down).to receive(:download).with('https://connector.test/media/dead', anything)
                                     .and_raise(Down::ConnectionError, 'connection refused')

    backend.download_media(download_command(model::MediaRef.url('https://connector.test/media/dead')))

    expect(Down).to have_received(:download).with('https://connector.test/media/abc', anything)
  end

  it 'asks again when the blob turns out to be gone mid-flight' do
    allow(Down).to receive(:download).with('https://connector.test/media/stale', anything).and_raise(Down::NotFound, 'gone')
    fresh = model::MediaRef.url('https://connector.test/media/stale', mime: 'image/jpeg').with(expires_at: 1.hour.from_now.to_i * 1000)

    backend.download_media(download_command(fresh))

    expect(client).to have_received(:call).once
    expect(Down).to have_received(:download).with('https://connector.test/media/abc', anything)
  end

  def download_command(ref)
    model::Commands::MessageDownloadMedia.new(chat: model::Address.phone('5541999990000'), message_id: '3EB0AAAA', ref: ref)
  end

  it 'answers fire-and-forget commands without waiting' do
    expect(client).not_to receive(:call)

    backend.mark_read(model::Commands::MessageMarkRead.new(chat: model::Address.phone('5541999990000'), message_ids: ['3EB0AAAA']))
    backend.disconnect
  end
end
