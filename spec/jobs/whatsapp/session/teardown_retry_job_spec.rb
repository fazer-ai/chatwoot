require 'rails_helper'

RSpec.describe Whatsapp::Session::TeardownRetryJob, :redis_streams do
  let(:prefix) { "watest#{SecureRandom.hex(4)}:" }
  let(:redis) { Redis.new(Redis::Config.app) }
  let(:session_id) { SecureRandom.uuid }

  around do |example|
    with_modified_env(WHATSAPP_CONNECTOR_REDIS_PREFIX: prefix) { example.run }
    keys = redis.keys("#{prefix}*")
    redis.del(*keys) if keys.any?
  end

  def frames(stream)
    redis.xrange("#{prefix}#{stream}").map(&:last)
  end

  context 'when no inbox holds the session any more' do
    # The inbox was destroyed or moved to another provider: the teardown is the last thing
    # anybody will ever ask of this session, so nothing stands in its way.
    it 'sends the delete again on the control stream, bounded by runtime and never by a deadline' do
      described_class.perform_now(session_id, 'session.delete')

      sent = frames('control')
      expect(sent.size).to eq(1)
      expect(sent.first).to include('type' => 'session.delete', 'sid' => session_id)
      expect(sent.first['deadline']).to be_nil
      expect(sent.first['max_runtime_ms']).to eq((Whatsapp::Session::Backends::Connector::Backend::TEARDOWN_RUNTIME * 1000).to_s)
    end

    it "sends the logout again on the session's own stream" do
      described_class.perform_now(session_id, 'session.logout')

      sent = frames("cmd:#{session_id}")
      expect(sent.size).to eq(1)
      expect(sent.first).to include('type' => 'session.logout', 'sid' => session_id)
      expect(sent.first['deadline']).to be_nil
    end
  end

  context 'when the inbox is still there' do
    let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
    let(:session_id) { channel.provider_config['session_id'] }

    # The operator disconnected it, the endpoint recorded it closed, and nobody asked to
    # connect it since: the teardown is still what the inbox wants.
    it 'sends it again while the inbox stays disconnected' do
      channel.update_provider_connection!({ 'connection' => 'close' })

      described_class.perform_now(session_id, 'session.delete')

      expect(frames('control').size).to eq(1)
    end

    # Pairing again writes `connecting` before it asks for anything, so a teardown sent now
    # would end the session the operator is setting up.
    it 'stands down once somebody asked to connect it again' do
      channel.update_provider_connection!({ 'connection' => 'connecting' })

      described_class.perform_now(session_id, 'session.delete')

      expect(frames('control')).to be_empty
    end

    # A session paired with the wrong account is the LogoutJob's, which has its own
    # schedule and its own check.
    it 'leaves a quarantined inbox to the logout job' do
      channel.update_provider_connection!({ 'connection' => 'close', 'error_code' => 'wrong_phone_number' })

      described_class.perform_now(session_id, 'session.logout')

      expect(frames("cmd:#{session_id}")).to be_empty
    end
  end
end
