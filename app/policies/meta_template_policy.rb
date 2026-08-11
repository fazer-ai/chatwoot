class MetaTemplatePolicy < ApplicationPolicy
  # Read: any agent-or-above can browse the template catalog. The sidebar
  # gate keeps the menu hidden for accounts without a Cloud WhatsApp
  # inbox, so agents on Baileys-only accounts never see this at all.
  def index?
    @account_user.administrator? || @account_user.manager? || @account_user.agent?
  end

  def show?
    index?
  end

  # Trigger an on-demand refresh from Meta. Same read audience — the sync
  # itself is a stateless refresh of `channel.message_templates`, not a
  # mutation of any user data.
  def sync?
    index?
  end

  # Reserved for the follow-up slices (Fatia 3+). Managers and
  # administrators can create/edit/delete; agents cannot.
  def create?
    @account_user.administrator? || @account_user.manager?
  end

  def update?
    create?
  end

  def destroy?
    create?
  end
end
