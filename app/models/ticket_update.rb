# A single row on a ticket's Atualização timeline (Meus Tickets → detail
# modal grid). Two writers create these:
#
# - Webhooks::Clickup::ProcessEventService when the ops team changes the
#   "Resposta para o Cliente" field on the ClickUp task. `user_id` is nil
#   and `actor_name` is 'Auris' — the entry represents the support team's
#   voice.
# - Api::V1::Accounts::TicketsController#add_comment when the operator (or
#   the manager) posts additional context from Meus Tickets. `user_id` is
#   set and `actor_name` is the user's display name at write time
#   (denormalized so a later rename doesn't rewrite history).
#
# The frontend groups them chronologically on the detail modal into a
# `data | quem | texto` table.
# == Schema Information
#
# Table name: ticket_updates
#
#  id         :bigint           not null, primary key
#  actor_name :string           not null
#  body       :text             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  ticket_id  :bigint           not null
#  user_id    :bigint
#
# Indexes
#
#  index_ticket_updates_on_ticket_id  (ticket_id)
#  index_ticket_updates_on_user_id    (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (ticket_id => tickets.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id)
#
class TicketUpdate < ApplicationRecord
  AURIS_ACTOR_NAME = 'Auris'.freeze

  belongs_to :ticket
  belongs_to :user, optional: true

  validates :body, presence: true, length: { maximum: 10_000 }
  validates :actor_name, presence: true

  scope :chronological, -> { order(created_at: :asc) }
end
