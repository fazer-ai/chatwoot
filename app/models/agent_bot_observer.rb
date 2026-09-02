# == Schema Information
#
# Table name: agent_bot_observers
#
#  id           :bigint           not null, primary key
#  status       :integer          default("active"), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  agent_bot_id :bigint           not null
#  inbox_id     :bigint           not null
#
# Indexes
#
#  index_agent_bot_observers_on_account_id                 (account_id)
#  index_agent_bot_observers_on_agent_bot_id               (agent_bot_id)
#  index_agent_bot_observers_on_inbox_id_and_agent_bot_id  (inbox_id,agent_bot_id) UNIQUE
#
# An agent bot that receives an inbox's events without answering it. The inbox's single
# `AgentBotInbox` stays the responder: it owns new conversations (Inbox#active_bot? starts them
# `pending`, assigned to it) and its exhausted deliveries hand the conversation to a human. An
# observer gets the same deliveries under `:agent_bot_observer_webhook`, owns nothing, and its
# failures escalate nothing.
class AgentBotObserver < ApplicationRecord
  validates :agent_bot_id, uniqueness: { scope: :inbox_id }
  before_validation :ensure_account_id

  belongs_to :inbox
  belongs_to :agent_bot
  belongs_to :account
  enum status: { active: 0, inactive: 1 }

  private

  def ensure_account_id
    self.account_id = inbox&.account_id
  end
end
