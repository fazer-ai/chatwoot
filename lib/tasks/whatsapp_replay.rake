namespace :whatsapp do
  # Replays a captured WhatsApp webhook payload (Baileys or Cloud) through the
  # real ingestion pipeline (Webhooks::WhatsappEventsJob), bypassing the HTTP
  # controller so you don't need the Meta signature (Cloud) or a live request.
  #
  # Usage:
  #   bundle exec rails "whatsapp:replay_webhook[tmp/payload.json]"
  #   bundle exec rails "whatsapp:replay_webhook[tmp/payload.json,+5511936199421]"
  #
  # The phone_number arg is required for Baileys payloads (used to find the
  # channel and inject its webhook_verify_token). Cloud payloads resolve the
  # channel from the embedded metadata, so the arg is optional there.
  desc 'Replay a captured WhatsApp webhook payload (Baileys/Cloud) through the parser'
  task :replay_webhook, %i[path phone_number] => :environment do |_task, args|
    raise 'usage: rake "whatsapp:replay_webhook[path/to/payload.json,+55...]"' if args[:path].blank?

    payload = JSON.parse(File.read(args[:path])).with_indifferent_access
    phone = args[:phone_number].presence || payload[:phone_number]
    payload[:phone_number] = phone if phone.present?

    channel = Channel::Whatsapp.find_by(phone_number: phone) if phone.present?

    # Fail fast on a Baileys-style payload (a phone was given) that resolves to no
    # channel, instead of silently no-opping inside the events job.
    abort "No WhatsApp channel found for phone #{phone.inspect}" if phone.present? && channel.nil?

    # Baileys verifies webhookVerifyToken inside the service, so inject the
    # channel's token (captured payloads usually omit/filter it).
    if channel&.provider == 'baileys' && payload[:webhookVerifyToken].blank?
      payload[:webhookVerifyToken] = channel.provider_config['webhook_verify_token']
    end

    Rails.logger.info("[whatsapp:replay_webhook] replaying #{args[:path]} (phone=#{phone.inspect})")
    puts "Replaying #{args[:path]}#{" -> #{channel.name} (#{channel.provider})" if channel}"
    Webhooks::WhatsappEventsJob.perform_now(payload)
    puts 'Done. Check the conversation / last message in the inbox.'
  end
end
