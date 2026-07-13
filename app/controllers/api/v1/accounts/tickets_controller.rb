class Api::V1::Accounts::TicketsController < Api::V1::Accounts::BaseController
  before_action :fetch_message, only: [:create]
  before_action :fetch_ticket, only: [:show, :add_comment]

  # Meus Tickets. The scope narrows via `TicketPolicy::Scope` — an agent
  # sees their own tickets, a manager or admin sees everything in the
  # account with an extra Agente column on the frontend.
  def index
    @tickets = policy_scope(Ticket)
    @tickets = @tickets.where(clickup_status_name: status_filter) if status_filter.present?
    # Meus Tickets has a "Ocultar finalizadas" checkbox that hides every
    # ticket whose ClickUp status collapsed to 'encerrado' (the AurisChat
    # closed state). Applied AFTER the status filter so the two can be
    # combined (e.g. filter=aberto has no encerrados anyway; hide_finished
    # with no filter drops just the closed ones).
    @tickets = @tickets.where.not(clickup_status_name: 'encerrado') if hide_finished?
    @tickets = @tickets.recent_first.page(params[:page])
  end

  def show
    authorize @ticket, :show?
  end

  def create
    authorize Ticket, :create?

    @ticket = ::Tickets::CreateService.new(
      user: Current.user,
      message: @message,
      params: ticket_params
    ).perform

    schedule_attachment_uploads(@ticket) if attachment_uploads.present?

    render :show, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def add_comment
    authorize @ticket, :add_comment?
    render json: { error: 'comment is required' }, status: :unprocessable_entity and return if params[:comment].blank?
    render json: { error: 'ticket not synced yet' }, status: :unprocessable_entity and return unless @ticket.sync_synced?

    comment_body = params[:comment].to_s
    ::Integrations::Clickup::AddCommentJob.perform_later(@ticket.id, comment_body, Current.user&.id)
    record_local_update(comment_body)
    broadcast_ticket_update

    head :accepted
  end

  private

  def fetch_message
    @message = Current.account.messages.find(params[:message_id])
  end

  def fetch_ticket
    @ticket = Current.account.tickets.find(params[:id])
  end

  def ticket_params
    params.permit(:relatar_problema, :comportamento_esperado)
  end

  def status_filter
    params[:status].to_s.strip.presence
  end

  def hide_finished?
    ActiveModel::Type::Boolean.new.cast(params[:hide_finished])
  end

  # Local half of add_comment: append a row to the ticket's Atualização
  # timeline immediately, so the operator sees their comment on the detail
  # modal without waiting for the ClickUp round-trip. `actor_name` is
  # snapshotted here — a later user rename doesn't rewrite history.
  def record_local_update(body)
    actor_name = Current.user&.name.presence || 'Agente'
    @ticket.ticket_updates.create!(user: Current.user, actor_name: actor_name, body: body)
  end

  # Push the fresh timeline to every open Meus Tickets tab (owner + every
  # admin/manager on the account). `notify: false` — the operator posted
  # the comment themselves and does not need to toast their own tab.
  def broadcast_ticket_update
    tokens = []
    tokens << @ticket.user.pubsub_token if @ticket.user&.pubsub_token.present?
    tokens.concat(@ticket.account.administrators.pluck(:pubsub_token))
    tokens = tokens.compact_blank.uniq
    return if tokens.blank?

    ::ActionCableBroadcastJob.perform_later(
      tokens,
      'ticket.updated',
      { account_id: @ticket.account_id, ticket: @ticket.push_event_data, notify: false }
    )
  end

  # PR2: attachments come in as multipart uploads. Persist each to
  # ActiveStorage first (cheap, temporary), then hand the blob off to a job
  # that streams it to ClickUp. Once ClickUp confirms, the local blob can
  # go away — ClickUp is the canonical store.
  def schedule_attachment_uploads(ticket)
    attachment_uploads.each do |file|
      blob = ActiveStorage::Blob.create_and_upload!(io: file.tempfile, filename: file.original_filename, content_type: file.content_type)
      ::Integrations::Clickup::AttachFileJob.perform_later(ticket.id, blob.signed_id)
    end
  end

  def attachment_uploads
    Array(params[:attachments]).compact
  end
end
