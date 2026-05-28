# == Schema Information
#
# Table name: internal_chat_poll_votes
#
#  id                           :bigint           not null, primary key
#  created_at                   :datetime         not null
#  internal_chat_poll_option_id :bigint           not null
#  user_id                      :bigint           not null
#
# Indexes
#
#  idx_ic_poll_votes_option                   (internal_chat_poll_option_id)
#  idx_ic_poll_votes_option_user              (internal_chat_poll_option_id,user_id) UNIQUE
#  index_internal_chat_poll_votes_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (internal_chat_poll_option_id => internal_chat_poll_options.id)
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
class InternalChat::PollVote < ApplicationRecord
  self.table_name = 'internal_chat_poll_votes'

  belongs_to :option, class_name: 'InternalChat::PollOption', foreign_key: :internal_chat_poll_option_id,
                      inverse_of: :votes, counter_cache: :votes_count
  belongs_to :user

  validates :user_id, uniqueness: { scope: :internal_chat_poll_option_id }
end

InternalChat::PollVote.prepend_mod_with('InternalChat::PollVote')
