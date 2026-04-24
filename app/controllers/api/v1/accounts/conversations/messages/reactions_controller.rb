class Api::V1::Accounts::Conversations::Messages::ReactionsController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_channel_supports_reactions
  before_action :fetch_target_message
  before_action :ensure_target_is_reactable

  MAX_EMOJI_BYTES = 32 # an emoji with skin tone + ZWJ sequences fits in <=32 bytes

  # The `messages.content_attributes` column is `json` but the model writes it
  # as a double-encoded JSON string (legacy `store coder: JSON`), so the `->>`
  # operator can't traverse it directly. `#>>'{}'` unwraps the outer encoding
  # back to a real JSON object that we can then cast to `jsonb` and query.
  CONTENT_ATTRIBUTES_JSONB = "(content_attributes#>>'{}')::jsonb".freeze

  def create
    emoji = reaction_params[:emoji].to_s
    return render(json: { error: 'Invalid emoji' }, status: :unprocessable_entity) if emoji.bytesize > MAX_EMOJI_BYTES

    result = apply_toggle!(emoji)

    return render(json: { error: 'Emoji cannot be empty without an active reaction' }, status: :unprocessable_entity) if result == :invalid

    # Dispatched after the lock commits so the worker reads the post-update row
    # (source_id cleared); inside the transaction it would still see the stale
    # source_id and SendOnChannelService would skip the send. CREATE goes through
    # Message#after_create_commit -> send_reply, which already runs post-commit,
    # so we only re-dispatch for UPDATEs.
    ::SendReplyJob.perform_later(result) if result.is_a?(Integer)

    # Cable broadcast so the chat list refreshes `last_non_activity_message`.
    # Message#after_update_commit only sends MESSAGE_UPDATED (touches
    # chat.messages on the frontend); without this, the conversation card
    # snapshot stays pointed at the pre-toggle reaction state. Touch
    # `updated_at` first so the frontend's out-of-order guard in
    # UPDATE_CONVERSATION can drop stale cables when the user toggles fast.
    @conversation.update_columns(updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    @conversation.dispatch_conversation_updated_event

    head :ok
  end

  private

  # Serialize concurrent operations from the same user against the same target
  # message. Without the lock, two near-simultaneous clicks would both observe
  # the same state and either create duplicates or step on each other's update.
  def apply_toggle!(emoji)
    outcome = nil
    @target_message.with_lock do
      existing = current_user_reaction
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

  # WhatsApp allows one reaction per (message, user). We mirror that in storage:
  # a single Message row holds the user's current reaction. Replacing the emoji
  # updates the row in-place, removing it sets content='' + deleted=true, and a
  # subsequent re-add resurrects the same row. This keeps the conversation
  # history clean instead of accumulating one Message per toggle.
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

    # Reset source_id so SendOnChannelService doesn't treat this as a message
    # echoed back from the provider and skip the resend. The provider assigns a
    # fresh source_id on success via send_session_message.
    existing.update!(content: new_content, content_attributes: new_attrs, source_id: nil)
  end

  def reaction_active?(message)
    return false if message.nil?

    message.content.present? && !message.content_attributes['deleted']
  end

  def ensure_channel_supports_reactions
    channel = @conversation.inbox.channel
    return if channel.respond_to?(:supports_reactions?) && channel.supports_reactions?

    render json: { error: 'Reactions are not supported on this channel' }, status: :unprocessable_entity
  end

  def fetch_target_message
    @target_message = @conversation.messages.find(params[:message_id])
  end

  def ensure_target_is_reactable
    return render(json: { error: 'Cannot react to private messages' }, status: :unprocessable_entity) if @target_message.private?
    return unless @target_message.reaction?

    render(json: { error: 'Cannot react to a reaction' }, status: :unprocessable_entity)
  end

  # Returns the most recent reaction Message we should mutate for the current
  # user. Two sources qualify:
  # - Reactions the agent created via Chatwoot UI (sender = Current.user).
  # - Multi-device echoes: the agent reacted from the WhatsApp mobile app on the
  #   same number as the inbox, so the message comes back outgoing without an
  #   agent. Without this fallback, a click on such a chip would create a brand
  #   new Chatwoot-side reaction and the original would never be removed from
  #   WhatsApp.
  def current_user_reaction
    matches = @conversation.messages
                           .where("#{CONTENT_ATTRIBUTES_JSONB}->>'is_reaction' = 'true'")
                           .where("(#{CONTENT_ATTRIBUTES_JSONB}->>'in_reply_to')::bigint = ?", @target_message.id)
                           .where(
                             '(sender_type = ? AND sender_id = ?) OR ' \
                             '(message_type = ? AND sender_type IS NULL AND sender_id IS NULL)',
                             'User', Current.user.id, Message.message_types[:outgoing]
                           )
    # Prefer the newest active row so a stale deleted echo can't hijack the
    # toggle target and either resurrect a removed reaction or leave the
    # active one untouched (creating a duplicate active state for the user).
    active = matches.where.not(content: '')
                    .where("COALESCE(#{CONTENT_ATTRIBUTES_JSONB}->>'deleted', 'false') != 'true'")
                    .reorder(created_at: :desc)
                    .first
    active || matches.reorder(created_at: :desc).first
  end

  def build_reaction_message!(emoji)
    Messages::MessageBuilder.new(
      Current.user,
      @conversation,
      ActionController::Parameters.new(
        message_type: 'outgoing',
        content: emoji,
        echo_id: reaction_params[:echo_id],
        content_attributes: {
          is_reaction: true,
          in_reply_to: @target_message.id
        }
      )
    ).perform
  end

  def reaction_params
    params.permit(:emoji, :echo_id)
  end
end
