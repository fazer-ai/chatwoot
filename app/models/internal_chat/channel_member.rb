# == Schema Information
#
# Table name: internal_chat_channel_members
#
#  id                       :bigint           not null, primary key
#  favorited                :boolean          default(FALSE), not null
#  last_read_at             :datetime
#  muted                    :boolean          default(FALSE), not null
#  role                     :integer          default("member"), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  internal_chat_channel_id :bigint           not null
#  user_id                  :bigint           not null
#
# Indexes
#
#  idx_ic_channel_members_channel_user             (internal_chat_channel_id,user_id) UNIQUE
#  idx_ic_channel_members_user_favorited           (user_id,favorited)
#  index_internal_chat_channel_members_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (internal_chat_channel_id => internal_chat_channels.id)
#  fk_rails_...  (user_id => users.id)
#
class InternalChat::ChannelMember < ApplicationRecord
  self.table_name = 'internal_chat_channel_members'

  belongs_to :channel, class_name: 'InternalChat::Channel', foreign_key: :internal_chat_channel_id, inverse_of: :channel_members
  belongs_to :user

  enum :role, { member: 0, admin: 1 }

  validates :user_id, uniqueness: { scope: :internal_chat_channel_id }

  scope :not_muted, -> { where(muted: false) }
  scope :muted, -> { where(muted: true) }
  scope :favorited, -> { where(favorited: true) }

  def unread_messages_count
    return 0 if last_read_at.blank?

    channel.messages.where('created_at > ?', last_read_at).count
  end
end

InternalChat::ChannelMember.prepend_mod_with('InternalChat::ChannelMember')
