# == Schema Information
#
# Table name: internal_chat_polls
#
#  id                       :bigint           not null, primary key
#  allow_revote             :boolean          default(TRUE), not null
#  expires_at               :datetime
#  multiple_choice          :boolean          default(FALSE), not null
#  public_results           :boolean          default(TRUE), not null
#  question                 :string           not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  internal_chat_message_id :bigint           not null
#
# Indexes
#
#  idx_ic_polls_message         (internal_chat_message_id)
#  idx_ic_polls_message_unique  (internal_chat_message_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (internal_chat_message_id => internal_chat_messages.id)
#
class InternalChat::Poll < ApplicationRecord
  self.table_name = 'internal_chat_polls'

  belongs_to :message, class_name: 'InternalChat::Message', foreign_key: :internal_chat_message_id, inverse_of: :poll

  has_many :options, class_name: 'InternalChat::PollOption', foreign_key: :internal_chat_poll_id,
                     dependent: :destroy, inverse_of: :poll
  has_many :votes, through: :options

  validates :question, presence: true

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def total_votes_count
    return options.sum(&:votes_count) if options.loaded?

    options.sum(:votes_count)
  end
end

InternalChat::Poll.prepend_mod_with('InternalChat::Poll')
