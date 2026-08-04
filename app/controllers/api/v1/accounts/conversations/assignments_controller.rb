class Api::V1::Accounts::Conversations::AssignmentsController < Api::V1::Accounts::Conversations::BaseController
  # assigns agent/team to a conversation
  def create
    if params.key?(:assignee_id) || agent_bot_assignment?
      set_agent
    elsif params.key?(:team_id)
      set_team
    else
      render json: nil
    end
  end

  private

  def set_agent
    resource = Conversations::AssignmentService.new(
      conversation: @conversation,
      assignee_id: params[:assignee_id],
      assignee_type: params[:assignee_type]
    ).perform

    render_agent(resource)
  end

  def render_agent(resource)
    case resource
    when User
      render partial: 'api/v1/models/agent', formats: [:json], locals: { resource: resource }
    when AgentBot
      render partial: 'api/v1/models/agent_bot_slim', formats: [:json], locals: { resource: resource }
    else
      render json: nil
    end
  end

  def set_team
    @team = Current.account.teams.find_by(id: params[:team_id])
    team_was_unchanged = @conversation.team_id == @team&.id
    @conversation.update!(team: @team)
    # Chatwoot's AssignmentHandler only auto-assigns when `team_id`
    # actually changes. When the IA re-escalates a conversation whose
    # team was already set (e.g. handoff #2 after the operator resolved
    # #1 without changing team), that early-return leaves the row with
    # a team but no assignee. Force the same round-robin explicitly, and
    # record the attempt so the IA→Humano audit reflects it.
    force_reassignment_on_unchanged_team if team_was_unchanged && @team.present? && @conversation.assignee_id.nil?
    render json: @team
  end

  def agent_bot_assignment?
    params[:assignee_type].to_s == 'AgentBot'
  end

  def force_reassignment_on_unchanged_team
    return unless @team.allow_auto_assign

    team_members_with_capacity = @conversation.inbox.member_ids_with_assignment_capacity & @team.members.ids
    agent = ::AutoAssignment::AgentAssignmentService.new(
      conversation: @conversation,
      allowed_agent_ids: team_members_with_capacity
    ).find_assignee

    @conversation.update!(assignee: agent) if agent

    # `team.changed` won't dispatch because team_id didn't actually
    # change — record the audit row here so the report shows the retry.
    ::AiAssignmentAttempt.record_for(@conversation)
  end
end
