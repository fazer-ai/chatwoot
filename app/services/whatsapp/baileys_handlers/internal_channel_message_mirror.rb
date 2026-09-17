class Whatsapp::BaileysHandlers::InternalChannelMessageMirror
  def initialize(source_inbox:, raw_message:, recipient_phone:)
    @source_inbox = source_inbox
    @raw_message = raw_message
    @recipient_phone = recipient_phone
  end

  def perform
    return unless raw_message.dig(:key, :fromMe)
    return if recipient_phone.blank?
    return if target_channel.blank?

    Whatsapp::IncomingMessageBaileysService.new(inbox: target_channel.inbox, params: mirrored_params).perform
  end

  private

  attr_reader :source_inbox, :raw_message, :recipient_phone

  def target_channel
    channels = Channel::Whatsapp.where(account_id: source_inbox.account_id).where.not(id: source_inbox.channel_id)
    @target_channel ||= channels.find do |channel|
      channel.provider == 'baileys' && channel.provider_connection['connection'] == 'open' &&
        normalized_phone(channel.phone_number) == recipient_phone
    end
  end

  def mirrored_params
    {
      webhookVerifyToken: target_channel.provider_config['webhook_verify_token'],
      event: 'messages.upsert',
      data: { type: 'notify', messages: [mirrored_message] }
    }
  end

  def mirrored_message
    message = raw_message.deep_dup
    message[:key] = mirrored_key(message[:key])
    message[:pushName] = source_inbox.name
    message[:verifiedBizName] = source_inbox.name
    message[:internalChannelMirror] = { sourceInboxId: source_inbox.id }
    message
  end

  def mirrored_key(key)
    source_phone = normalized_phone(source_inbox.channel.phone_number)
    source_lid = source_contact_lid
    return key.merge(fromMe: false, remoteJid: "#{source_phone}@s.whatsapp.net").except(:remoteJidAlt, :addressingMode) if source_lid.blank?

    key.merge(
      fromMe: false,
      remoteJid: "#{source_lid}@lid",
      remoteJidAlt: "#{source_phone}@s.whatsapp.net",
      addressingMode: 'lid'
    )
  end

  def source_contact_lid
    contact = source_inbox.account.contacts.find_by(phone_number: source_inbox.channel.phone_number)
    contact&.identifier&.delete_suffix('@lid')
  end

  def normalized_phone(phone_number)
    phone_number.to_s.delete('+')
  end
end
