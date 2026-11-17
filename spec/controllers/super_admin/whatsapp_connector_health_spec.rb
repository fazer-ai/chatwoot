require 'rails_helper'

# config/initializers/whatsapp_connector_health.rb: the connector on the super admin health page,
# added to upstream's page without editing its controller.
RSpec.describe 'Super Admin instance status: WhatsApp connector', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:prefix) { "wahealth#{SecureRandom.hex(4)}:" }
  let(:redis) { Redis.new(Redis::Config.app) }

  around do |example|
    with_modified_env(WHATSAPP_CONNECTOR_REDIS_PREFIX: prefix, WHATSAPP_CONNECTOR_ENABLED: nil) { example.run }
    keys = redis.keys("#{prefix}*")
    redis.del(*keys) if keys.any?
  end

  def page
    sign_in(super_admin, scope: :super_admin)
    get '/super_admin/instance_status'
    expect(response).to have_http_status(:success)
    response.body
  end

  def register(id, version)
    redis.hset("#{prefix}instance:#{id}", 'version', version, 'protocol_min', '1', 'protocol_max', '1')
    redis.sadd("#{prefix}instances", id)
  end

  it 'lists each live instance with its version, and drops one whose entry expired' do
    register('cw-worker-1', '0.9.0')
    register('cw-worker-2', '0.9.1')
    redis.del("#{prefix}instance:cw-worker-2")

    body = page

    expect(body).to include('WhatsApp (native) connector', 'running', 'WhatsApp connector cw-worker-1', '0.9.0')
    expect(body).not_to include('not running')
    expect(body).not_to include('cw-worker-2')
    expect(body).to include('Chatwoot version', 'Postgres alive')
  end

  it 'says it is not running and why the last start failed' do
    redis.set("#{prefix}embedded:cw-worker-1",
              { error: 'connector did not start: schema whatsapp_connector does not exist', at: '2026-11-17T11:00:00Z' }.to_json)

    body = page

    expect(body).to include('not running', 'WhatsApp connector start error (cw-worker-1)',
                            'schema whatsapp_connector does not exist')
  end

  it 'leaves the connector out of an installation that turned it off' do
    register('cw-worker-1', '0.9.0')

    with_modified_env(WHATSAPP_CONNECTOR_ENABLED: 'false') do
      expect(page).not_to include('WhatsApp (native) connector')
    end
  end
end
