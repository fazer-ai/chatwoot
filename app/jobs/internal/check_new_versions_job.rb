class Internal::CheckNewVersionsJob < ApplicationJob
  queue_as :scheduled_jobs

  # NOTE: Spread requests over a configurable window to avoid thundering herd on hub server.
  # When triggered by cron, the job reschedules itself with a deterministic delay
  # based on the installation identifier, then executes the actual work.
  JITTER_WINDOW_SECONDS = ENV.fetch('VERSION_CHECK_JITTER_WINDOW_MINUTES', 30).to_i.minutes.to_i

  def perform(jitter_applied: false)
    unless jitter_applied || Rails.env.test?
      jitter_seconds = deterministic_jitter_seconds
      if jitter_seconds.positive?
        self.class.set(wait: jitter_seconds.seconds).perform_later(jitter_applied: true)
        return
      end
    end

    @instance_info = sync_with_hub
    update_version_info
  end

  private

  def deterministic_jitter_seconds
    identifier = ChatwootHub.installation_identifier
    return 0 if identifier.blank?

    Digest::MD5.hexdigest(identifier).to_i(16) % JITTER_WINDOW_SECONDS
  end

  def sync_with_hub
    ChatwootHub.sync_with_hub
  end

  def update_version_info
    return if @instance_info.blank? || @instance_info['version'].blank?

    ::Redis::Alfred.set(::Redis::Alfred::LATEST_CHATWOOT_VERSION, @instance_info['version'])
  end
end

Internal::CheckNewVersionsJob.prepend_mod_with('Internal::CheckNewVersionsJob')
