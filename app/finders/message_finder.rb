class MessageFinder
  PAGE_LIMIT = 20

  # `messages.content_attributes` is `json` but the model stores it as a
  # double-encoded string (legacy `store coder: JSON`), so `->>` can't traverse
  # it directly — `#>>'{}'` unwraps the outer encoding into proper jsonb.
  NON_REACTION_CLAUSE = "((content_attributes#>>'{}')::jsonb->>'is_reaction') IS DISTINCT FROM 'true'".freeze

  def initialize(conversation, params)
    @conversation = conversation
    @params = params
  end

  def perform
    current_messages
  end

  private

  def conversation_messages
    @conversation.messages.includes(:attachments, :sender, sender: { avatar_attachment: [:blob] })
  end

  def messages
    return conversation_messages if @params[:filter_internal_messages].blank?

    conversation_messages.where.not('private = ? OR message_type = ?', true, 2)
  end

  def current_messages
    if @params[:after].present? && @params[:before].present?
      messages_between(@params[:after].to_i, @params[:before].to_i)
    elsif @params[:before].present?
      messages_before(@params[:before].to_i)
    elsif @params[:after].present?
      messages_after(@params[:after].to_i)
    else
      messages_latest
    end
  end

  def messages_after(after_id)
    messages.reorder('created_at asc').where('id > ?', after_id).limit(100)
  end

  def messages_before(before_id)
    page_window(messages.where('id < ?', before_id))
  end

  def messages_between(after_id, before_id)
    messages.reorder('created_at asc').where('id >= ? AND id < ?', after_id, before_id).limit(1000)
  end

  def messages_latest
    page_window(messages)
  end

  # Reactions don't count toward the page limit — otherwise a heavily-reacted
  # message can flood the latest page and hide regular messages from the UI on
  # initial load. Pick the most recent non-reactions, then add only the
  # reactions whose target is inside that window so chips render alongside
  # their parents and orphan reactions on older messages don't bloat the page.
  def page_window(scope)
    # Drop `includes(:sender, ...)` for the id-only probe to avoid Rails trying
    # to eager-load the polymorphic sender association (which would error).
    # `minimum(:id)` would silently aggregate over the FULL relation (Rails
    # drops the limit), pulling in old messages and blowing up the page. Pluck
    # the limited window first and take the min in Ruby.
    bare = scope.except(:includes)
    window_ids = bare.where(NON_REACTION_CLAUSE).reorder('created_at desc').limit(PAGE_LIMIT).pluck(:id)
    return scope.none if window_ids.empty?

    json_path = "(content_attributes#>>'{}')::jsonb"
    # `Message#ensure_in_reply_to` always populates content_attributes['in_reply_to']
    # when either the internal id or external source_id resolves to a parent in the
    # same conversation, so a single jsonb path scopes reactions to the windowed
    # parents reliably.
    reaction_in_window = "((#{json_path}->>'is_reaction') = 'true' AND " \
                         "(#{json_path}->>'in_reply_to')::bigint IN (:ids))"
    scope.where("id IN (:ids) OR #{reaction_in_window}", ids: window_ids)
         .reorder('created_at asc')
  end
end

MessageFinder.prepend_mod_with('MessageFinder')
