# Asks the connector again for every native inbox that has a session to resume, so that the
# ones paired while the session layer asked it to refuse every call stop doing it
# (fazer-ai/chatwoot#850). The connector keeps the policy of the last connect and stands on
# it when the session comes back, so without a new connect those inboxes would go on ending
# every call on the operator's phone too.
#
# Each inbox goes through ApplyProxyJob, which sends the whole desired state and retries while
# the connector is down. They are spread a few at a time, the pacing of the
# `whatsapp:session:reassert` rake: `wa:control` is one stream for the whole fleet, and every
# account asked dials.
#
# Run again by hand: Migration::NativeCallPolicyJob.perform_now
class Migration::NativeCallPolicyJob < ApplicationJob
  queue_as :async_database_migration

  BATCH = 4
  PAUSE = 10.seconds

  def perform
    channels = Channel::Whatsapp.where(provider: 'native').select(&:resumable_session?)

    channels.each_slice(BATCH).with_index do |slice, index|
      slice.each { |channel| Whatsapp::Session::ApplyProxyJob.set(wait: index * PAUSE).perform_later(channel.id) }
    end

    Rails.logger.info("[native-call-policy] asked again inboxes=#{channels.size}")
  end
end
