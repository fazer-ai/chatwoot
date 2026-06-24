# == Schema Information
#
# Table name: ai_assignment_attempts
#
#  id                :bigint           not null, primary key
#  online_user_ids   :bigint           default([]), not null, is an Array
#  created_at        :datetime         not null
#  account_id        :bigint           not null
#  agent_assigned_id :bigint
#  conversation_id   :bigint           not null
#  team_id           :bigint           not null
#  triggered_by_id   :bigint           not null
#
# Indexes
#
#  index_ai_assignment_attempts_on_account_id_and_created_at  (account_id,created_at)
#  index_ai_assignment_attempts_on_agent_assigned_id          (agent_assigned_id)
#  index_ai_assignment_attempts_on_conversation_id            (conversation_id)
#  index_ai_assignment_attempts_on_online_user_ids            (online_user_ids) USING gin
#  index_ai_assignment_attempts_on_team_id                    (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => cascade
#
class AiAssignmentAttempt < ApplicationRecord
  # Detection rule for "this assignment came from the IA". The n8n flow
  # POSTs `/conversations/:id/assignments` using the Chatwoot API
  # credential of a user whose name carries "Auris" (e.g. "IA | Auris").
  # Manual assignments by a human agent leave `Current.user` set to that
  # human and won't match — that's by design: this audit measures the IA
  # flow only.
  IA_USER_NAME_PATTERN = /Auris/i

  belongs_to :conversation
  belongs_to :account
  belongs_to :team
  belongs_to :agent_assigned, class_name: 'User', optional: true
  belongs_to :triggered_by, class_name: 'User'

  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :for_inbox, lambda { |inbox_id|
    joins(:conversation).where(conversations: { inbox_id: inbox_id })
  }

  def self.ia_driven_user?(user)
    return false if user.nil?

    user.name.to_s.match?(IA_USER_NAME_PATTERN)
  end

  # Categorises the attempt for the "IA → Humano" report. Mirrors the
  # status tags the old activity-message-based report emitted, but is
  # now derivable from a single row instead of regex + snapshot join.
  def status_tag
    return 'assigned_via_team'   if agent_assigned_id.present? && online_user_ids.include?(agent_assigned_id)
    return 'assigned_via_team_offline' if agent_assigned_id.present?
    return 'failed_no_online'    if online_user_ids.empty?

    'failed_with_online'
  end
end
