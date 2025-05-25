module Whatsapp::BaileysHandlers::Helpers
  def message_id
    @raw_message[:key][:id]
  end

  def incoming?
    !@raw_message[:key][:fromMe]
  end

  def jid_type # rubocop:disable Metrics/CyclomaticComplexity
    jid = @raw_message[:key][:remoteJid]
    server = jid.split('@').last

    # NOTE: Based on Baileys internal functions
    # https://github.com/WhiskeySockets/Baileys/blob/v6.7.16/src/WABinary/jid-utils.ts#L48-L58
    case server
    when 's.whatsapp.net', 'c.us'
      'user'
    when 'g.us'
      'group'
    when 'lid'
      'lid'
    when 'broadcast'
      jid.start_with?('status@') ? 'status' : 'broadcast'
    when 'newsletter'
      'newsletter'
    when 'call'
      'call'
    else
      'unknown'
    end
  end

  def message_type # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/MethodLength
    msg = @raw_message[:message]
    @message_type ||= if msg.key?(:conversation) || msg.dig(:extendedTextMessage, :text).present?
                        'text'
                      elsif msg.key?(:imageMessage)
                        'image'
                      elsif msg.key?(:audioMessage)
                        'audio'
                      elsif msg.key?(:videoMessage)
                        'video'
                      elsif msg.key?(:documentMessage)
                        'file'
                      elsif msg.key?(:stickerMessage)
                        'sticker'
                      elsif msg.key?(:reactionMessage)
                        'reaction'
                      elsif msg.key?(:protocolMessage)
                        'protocol'
                      else
                        'unsupported'
                      end
  end

  def message_content
    case message_type
    when 'text'
      @raw_message.dig(:message, :conversation) || @raw_message.dig(:message, :extendedTextMessage, :text)
    when 'image'
      @raw_message.dig(:message, :imageMessage, :caption)
    when 'video'
      @raw_message.dig(:message, :videoMessage, :caption)
    when 'reaction'
      @raw_message.dig(:message, :reactionMessage, :text)
    end
  end

  def file_content_type
    return :image if message_type.in?(%w[image sticker])
    return :video if message_type.in?(%w[video video_note])
    return :audio if message_type == 'audio'

    :file
  end

  def message_mimetype
    case message_type
    when 'image'
      @raw_message.dig(:message, :imageMessage, :mimetype)
    when 'sticker'
      @raw_message.dig(:message, :stickerMessage, :mimetype)
    when 'video'
      @raw_message.dig(:message, :videoMessage, :mimetype)
    when 'audio'
      @raw_message.dig(:message, :audioMessage, :mimetype)
    when 'file'
      @raw_message.dig(:message, :documentMessage, :mimetype)
    end
  end
end
