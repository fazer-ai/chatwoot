# == Schema Information
#
# Table name: internal_chat_reactions
#
#  id                       :bigint           not null, primary key
#  emoji                    :string           not null
#  created_at               :datetime         not null
#  internal_chat_message_id :bigint           not null
#  user_id                  :bigint           not null
#
# Indexes
#
#  idx_ic_reactions_message                  (internal_chat_message_id)
#  idx_ic_reactions_message_user_emoji       (internal_chat_message_id,user_id,emoji) UNIQUE
#  index_internal_chat_reactions_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (internal_chat_message_id => internal_chat_messages.id)
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
class InternalChat::Reaction < ApplicationRecord
  self.table_name = 'internal_chat_reactions'

  belongs_to :message, class_name: 'InternalChat::Message', foreign_key: :internal_chat_message_id, inverse_of: :reactions
  belongs_to :user

  validates :emoji, presence: true
  validates :emoji, uniqueness: { scope: [:internal_chat_message_id, :user_id] }
end

InternalChat::Reaction.prepend_mod_with('InternalChat::Reaction')
