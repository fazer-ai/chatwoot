require 'rails_helper'

RSpec.describe Migration::NativeCallPolicyJob do
  def native(connection)
    create(:channel_whatsapp, provider: 'native', sync_templates: false, validate_provider_config: false).tap do |channel|
      channel.provider_connection = connection
      channel.save!(validate: false)
    end
  end

  # The connector keeps the call policy of the last connect and stands on it when the session
  # comes back, so an inbox paired before the fix keeps refusing calls until it is asked again.
  # One that is paired but down is asked too: it resumes on the policy it was last given.
  it 'asks again every native inbox that has a session to resume, and no other' do
    open = native('connection' => 'open')
    down = native('connection' => 'close', 'phone_number' => '5541999991111')
    native('connection' => 'close')
    create(:channel_whatsapp, provider: 'uazapi', sync_templates: false, validate_provider_config: false,
                              provider_connection: { 'connection' => 'open' })

    expect { described_class.perform_now }
      .to have_enqueued_job(Whatsapp::Session::ApplyProxyJob).exactly(2).times
    expect(Whatsapp::Session::ApplyProxyJob).to have_been_enqueued.with(open.id)
    expect(Whatsapp::Session::ApplyProxyJob).to have_been_enqueued.with(down.id)
  end

  # `wa:control` is one stream for the whole fleet, and every account asked dials: a deploy that
  # asks them all in the same second is the stampede the rake's pacing exists to avoid.
  it 'spreads the inboxes over time, a few at a time' do
    channels = Array.new(5) { native('connection' => 'open') }

    freeze_time do
      described_class.perform_now

      scheduled = ActiveJob::Base.queue_adapter.enqueued_jobs
                                 .select { |job| job['job_class'] == 'Whatsapp::Session::ApplyProxyJob' }
                                 .to_h { |job| [job['arguments'].first, job['scheduled_at']] }
      first_four = channels.first(4).map { |channel| scheduled[channel.id] }
      expect(first_four.uniq.size).to eq(1)
      expect(Time.zone.parse(scheduled[channels.last.id]) - Time.zone.parse(first_four.first)).to eq(10)
    end
  end
end
