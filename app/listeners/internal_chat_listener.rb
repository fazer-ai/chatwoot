class InternalChatListener < BaseListener
  include Events::Types

  def internal_chat_message_created(event)
    message = event.data[:message]
    channel = message.channel
    account = message.account
    tokens = member_tokens(channel)

    broadcast(account, tokens, INTERNAL_CHAT_MESSAGE_CREATED, message_event_data(message))
  end

  def internal_chat_message_updated(event)
    message = event.data[:message]
    channel = message.channel
    account = message.account
    tokens = member_tokens(channel)

    broadcast(account, tokens, INTERNAL_CHAT_MESSAGE_UPDATED, message_event_data(message))
  end

  def internal_chat_message_deleted(event)
    message_data = event.data[:message_data]
    account = Account.find_by(id: message_data[:account_id])
    channel = InternalChat::Channel.find_by(id: message_data[:channel_id])
    return if account.blank? || channel.blank?
    return unless channel.account_id == account.id

    tokens = member_tokens(channel)
    broadcast(account, tokens, INTERNAL_CHAT_MESSAGE_DELETED, message_data)
  end

  def internal_chat_channel_updated(event)
    channel = event.data[:channel]
    account = channel.account
    tokens = member_tokens(channel)

    broadcast(account, tokens, INTERNAL_CHAT_CHANNEL_UPDATED,
              {
                id: channel.id,
                name: channel.name,
                description: channel.description,
                channel_type: channel.channel_type,
                status: channel.status,
                category_id: channel.category_id,
                last_activity_at: channel.last_activity_at
              })
  end

  def internal_chat_typing_on(event)
    channel = event.data[:channel]
    user = event.data[:user]
    account = channel.account
    tokens = member_tokens(channel, exclude_user: user)

    broadcast(account, tokens, INTERNAL_CHAT_TYPING_ON, { channel: { id: channel.id }, user: user.push_event_data })
  end

  def internal_chat_typing_off(event)
    channel = event.data[:channel]
    user = event.data[:user]
    account = channel.account
    tokens = member_tokens(channel, exclude_user: user)

    broadcast(account, tokens, INTERNAL_CHAT_TYPING_OFF, { channel: { id: channel.id }, user: user.push_event_data })
  end

  def internal_chat_poll_voted(event)
    poll = event.data[:poll]
    message = event.data[:message]
    channel = message.channel
    account = message.account
    tokens = member_tokens(channel)

    broadcast(account, tokens, INTERNAL_CHAT_POLL_VOTED, poll_event_data(poll))
  end

  def internal_chat_reaction_created(event)
    reaction = event.data[:reaction]
    message = reaction.message
    channel = message.channel
    account = message.account
    tokens = member_tokens(channel)

    broadcast(account, tokens, INTERNAL_CHAT_REACTION_CREATED, reaction_event_data(reaction))
  end

  def internal_chat_reaction_deleted(event)
    reaction_data = event.data[:reaction_data]
    account = Account.find_by(id: reaction_data[:account_id])
    channel = InternalChat::Channel.find_by(id: reaction_data[:channel_id])
    return if account.blank? || channel.blank?
    return unless channel.account_id == account.id

    tokens = member_tokens(channel)
    broadcast(account, tokens, INTERNAL_CHAT_REACTION_DELETED, reaction_data)
  end

  private

  def member_tokens(channel, exclude_user: nil)
    users = if channel.channel_type_public_channel?
              channel.account.users
            else
              channel.members
            end

    tokens = users.pluck(:pubsub_token)
    tokens -= [exclude_user.pubsub_token] if exclude_user.present?
    tokens
  end

  def message_event_data(message)
    {
      id: message.id,
      content: message.content,
      content_type: message.content_type,
      content_attributes: message.content_attributes,
      internal_chat_channel_id: message.internal_chat_channel_id,
      sender: message.sender.push_event_data,
      parent_id: message.parent_id,
      echo_id: message.echo_id,
      replies_count: message.replies.size,
      created_at: message.created_at,
      updated_at: message.updated_at,
      reactions: message.reactions.map { |r| { id: r.id, emoji: r.emoji, user_id: r.user_id } },
      attachments: message.attachments.map do |a|
        { id: a.id, file_type: a.file_type, external_url: a.external_url, extension: a.extension }
      end
    }
  end

  def poll_event_data(poll)
    {
      id: poll.id,
      question: poll.question,
      internal_chat_message_id: poll.internal_chat_message_id,
      options: poll.options.ordered.includes(votes: :user).map do |option|
        {
          id: option.id,
          text: option.text,
          votes_count: option.votes.size,
          voters: option.votes.map { |v| v.user.push_event_data }
        }
      end,
      total_votes: poll.total_votes_count
    }
  end

  def reaction_event_data(reaction)
    {
      id: reaction.id,
      emoji: reaction.emoji,
      user: reaction.user.push_event_data,
      internal_chat_message_id: reaction.internal_chat_message_id,
      created_at: reaction.created_at
    }
  end

  def broadcast(account, tokens, event_name, data)
    return if tokens.blank?

    payload = data.merge(account_id: account.id)
    ::ActionCableBroadcastJob.perform_later(tokens.uniq, event_name, payload)
  end
end
