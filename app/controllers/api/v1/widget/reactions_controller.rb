# Lets the customer side (the simulator iframe, or any widget that
# fronts a channel marked `supports_reactions?`) toggle a reaction on
# a message that lives in its current conversation. Mirrors the
# behaviour of
# `Api::V1::Accounts::Conversations::Messages::ReactionsController`
# but the reacting party is the @contact set up by
# `Api::V1::Widget::BaseController#set_contact`, so the persisted
# Message row is `message_type: :incoming` instead of `:outgoing`.
class Api::V1::Widget::ReactionsController < Api::V1::Widget::BaseController
  include Events::Types

  before_action :set_target_message
  before_action :ensure_channel_supports_reactions
  before_action :ensure_target_is_reactable

  MAX_EMOJI_BYTES = 32
  CONTENT_ATTRIBUTES_JSONB = "(content_attributes#>>'{}')::jsonb".freeze
  EMOJI_PROPERTY_RE = /[\p{Extended_Pictographic}\p{Regional_Indicator}\u{20E3}]/

  def create
    return render(json: { error: 'emoji is required' }, status: :unprocessable_entity) unless params[:emoji].is_a?(String)

    emoji = params[:emoji].to_s
    return render(json: { error: 'Invalid emoji' }, status: :unprocessable_entity) unless emoji_payload_valid?(emoji)

    result = apply_toggle!(emoji)
    return render(json: { error: 'Emoji cannot be empty without an active reaction' }, status: :unprocessable_entity) if result == :invalid

    head :ok
  end

  private

  def apply_toggle!(emoji)
    outcome = nil
    @target_message.with_lock do
      existing = current_contact_reaction
      if emoji.blank? && !reaction_active?(existing)
        outcome = :invalid
        next
      end
      outcome = mutate_reaction!(emoji, existing)
    end
    outcome
  end

  def mutate_reaction!(emoji, existing)
    if existing.present?
      update_existing_reaction!(existing, emoji)
      existing.id
    elsif emoji.present?
      build_reaction_message!(emoji)
      :created
    end
  end

  def update_existing_reaction!(existing, emoji)
    is_removing = reaction_active?(existing) && (emoji.blank? || existing.content == emoji)
    new_attrs = existing.content_attributes.dup

    if is_removing
      new_content = ''
      new_attrs['deleted'] = true
    else
      new_content = emoji
      new_attrs.delete('deleted')
    end

    existing.update!(content: new_content, content_attributes: new_attrs, source_id: nil)
  end

  def reaction_active?(message)
    return false if message.nil?

    message.content.present? && !message.content_attributes['deleted']
  end

  def emoji_payload_valid?(emoji)
    return true if emoji.empty?
    return false if emoji.bytesize > MAX_EMOJI_BYTES
    return false if emoji.each_grapheme_cluster.to_a.length != 1

    emoji.match?(EMOJI_PROPERTY_RE)
  end

  def set_target_message
    @target_message = Message.find_by(id: params[:message_id])
    raise ActiveRecord::RecordNotFound if @target_message.nil?

    @conversation = @target_message.conversation
    # The contact can only react to messages that belong to its own
    # contact_inbox; anything else would be a cross-contact poke.
    raise ActiveRecord::RecordNotFound unless @conversation.contact_inbox_id == @contact_inbox.id
  end

  def ensure_channel_supports_reactions
    channel = @conversation.inbox.channel
    return if channel.respond_to?(:supports_reactions?) && channel.supports_reactions?

    render json: { error: 'Reactions are not supported on this channel' }, status: :unprocessable_entity
  end

  def ensure_target_is_reactable
    error = target_unreactable_error
    return if error.nil?

    render(json: { error: error }, status: :unprocessable_entity)
  end

  def target_unreactable_error # rubocop:disable Metrics/CyclomaticComplexity
    return 'Cannot react to private messages' if @target_message.private?
    return 'Cannot react to a reaction' if @target_message.reaction?
    return 'Cannot react to deleted messages' if @target_message.content_attributes['deleted']
    return 'Cannot react to activity messages' if @target_message.activity?
    return 'Cannot react to template messages' if @target_message.template?
    return 'Cannot react to failed messages' if @target_message.failed?
    return 'Cannot react to unsupported messages' if @target_message.content_attributes['is_unsupported']

    nil
  end

  # Match against the same (in_reply_to, is_reaction) shape the dashboard
  # controller uses, but scope by sender = contact instead of user.
  def current_contact_reaction
    @conversation.messages
                 .where("#{CONTENT_ATTRIBUTES_JSONB}->>'is_reaction' = 'true'")
                 .where("(#{CONTENT_ATTRIBUTES_JSONB}->>'in_reply_to')::bigint = :message_id", message_id: @target_message.id)
                 .where(sender_type: 'Contact', sender_id: @contact.id)
                 .reorder(created_at: :desc)
                 .first
  end

  # Widget callers bypass `Messages::MessageBuilder` because it refuses
  # to mint incoming messages for non-API inboxes (the builder is the
  # dashboard's outgoing path). The widget itself writes the row
  # directly in `Api::V1::Widget::MessagesController#create`, so we
  # mirror that here and rely on `Message`'s own `after_create_commit`
  # callbacks for the cable broadcast and event dispatch.
  def build_reaction_message!(emoji)
    @conversation.messages.create!(
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      sender: @contact,
      message_type: :incoming,
      content: emoji,
      content_attributes: {
        is_reaction: true,
        in_reply_to: @target_message.id
      }
    )
  end
end
