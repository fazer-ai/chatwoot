class Internal::CheckNewVersionsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    @instance_info = sync_with_hub
    update_version_info
  end

  private

  def sync_with_hub
    ChatwootHub.sync_with_hub
  end

  def update_version_info
    return if @instance_info.blank? || @instance_info['version'].blank?

    ::Redis::Alfred.set(::Redis::Alfred::LATEST_CHATWOOT_VERSION, @instance_info['version'])
  end
end

Internal::CheckNewVersionsJob.prepend_mod_with('Internal::CheckNewVersionsJob')
