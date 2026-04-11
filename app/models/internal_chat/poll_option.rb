# == Schema Information
#
# Table name: internal_chat_poll_options
#
#  id                    :bigint           not null, primary key
#  emoji                 :string
#  image_url             :string
#  position              :integer          default(0), not null
#  text                  :string           not null
#  votes_count           :integer          default(0), not null
#  created_at            :datetime         not null
#  internal_chat_poll_id :bigint           not null
#
# Indexes
#
#  idx_ic_poll_options_poll      (internal_chat_poll_id)
#  idx_ic_poll_options_poll_pos  (internal_chat_poll_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (internal_chat_poll_id => internal_chat_polls.id)
#
class InternalChat::PollOption < ApplicationRecord
  self.table_name = 'internal_chat_poll_options'

  belongs_to :poll, class_name: 'InternalChat::Poll', foreign_key: :internal_chat_poll_id, inverse_of: :options

  has_many :votes, class_name: 'InternalChat::PollVote', foreign_key: :internal_chat_poll_option_id,
                   dependent: :destroy, inverse_of: :option

  validates :text, presence: true

  scope :ordered, -> { order(position: :asc) }
end

InternalChat::PollOption.prepend_mod_with('InternalChat::PollOption')
