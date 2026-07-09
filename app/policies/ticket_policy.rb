# Feedback tickets — agents, managers, and administrators of the ticket's
# account can open one. Reading follows the "manager sees everything, agent
# sees own" split the operator asked for.
class TicketPolicy < ApplicationPolicy
  def create?
    account_member?
  end

  def index?
    account_member?
  end

  # A specific ticket is visible when either the requester is a
  # manager/administrator on the account (they see the whole "Meus Tickets"
  # table with an extra Agente column) or they are the agent who opened it.
  # An agent viewing another agent's ticket returns 404, not 403 — we do not
  # leak the existence of a cross-agent ticket.
  def show?
    return false unless account_member?
    return true if administrator? || manager?

    record.user_id == user.id
  end

  # Adding comments: same as show. The frontend also gates the comment box on
  # the ticket detail modal — this is the backend enforcement.
  def add_comment?
    show?
  end

  # Pundit resolves this whenever a controller calls `policy_scope(Ticket)`
  # (Meus Tickets index) — narrow the visible set based on role.
  class Scope < Scope
    def resolve
      base = scope.where(account_id: account.id)
      return base if account_user&.administrator? || account_user&.manager?

      base.where(user_id: user.id)
    end
  end

  private

  def account_member?
    return false if account_user.blank?

    account_user.administrator? || account_user.manager? || account_user.agent?
  end

  def administrator?
    account_user&.administrator?
  end

  def manager?
    account_user&.manager?
  end
end
