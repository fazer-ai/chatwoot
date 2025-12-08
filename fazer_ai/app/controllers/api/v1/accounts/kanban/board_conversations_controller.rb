# frozen_string_literal: true

class Api::V1::Accounts::Kanban::BoardConversationsController < Api::V1::Accounts::Kanban::BaseController
  before_action :set_board

  def index
    authorize @board, :conversations?

    if @board.inbox_ids.empty?
      render json: { payload: [] }
      return
    end

    @conversations = fetch_conversations
    render json: {
      payload: build_payload(@conversations),
      meta: build_meta(@conversations)
    }
  end

  private

  def set_board
    @board = policy_scope(FazerAi::Kanban::Board).find(params[:board_id])
  end

  def fetch_conversations
    scope = Current.account.conversations.where(inbox_id: @board.inbox_ids)
                   .includes(:inbox, :contact)

    scope = filter_by_search_query(scope) if params[:q].present?

    scope.order(Arel.sql('CASE WHEN status = 1 THEN 1 ELSE 0 END'), created_at: :desc).page(params[:page]).per(20)
  end

  def filter_by_search_query(scope)
    query = params[:q].to_s.strip
    scope.joins(:contact).where(
      'cast(conversations.display_id as text) ILIKE :search ' \
      'OR contacts.name ILIKE :search ' \
      'OR contacts.email ILIKE :search ' \
      'OR contacts.phone_number ILIKE :search ' \
      'OR contacts.identifier ILIKE :search',
      search: "%#{query}%"
    )
  end

  def build_payload(conversations) # rubocop:disable Metrics/MethodLength
    conversations.map do |c|
      {
        id: c.id,
        display_id: c.display_id,
        status: c.status,
        kanban_task_id: c.kanban_task_id,
        inbox: {
          id: c.inbox.id,
          name: c.inbox.name,
          channel_type: c.inbox.channel_type
        },
        contact: {
          id: c.contact.id,
          name: c.contact.name,
          email: c.contact.email,
          avatar_url: c.contact.avatar_url
        },
        created_at: c.created_at.to_i
      }
    end
  end

  def build_meta(conversations)
    {
      count: conversations.total_count,
      current_page: conversations.current_page,
      total_pages: conversations.total_pages
    }
  end
end
