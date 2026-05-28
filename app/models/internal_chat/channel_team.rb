# == Schema Information
#
# Table name: internal_chat_channel_teams
#
#  id                       :bigint           not null, primary key
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  internal_chat_channel_id :bigint           not null
#  team_id                  :bigint           not null
#
# Indexes
#
#  idx_ic_channel_teams_channel_team             (internal_chat_channel_id,team_id) UNIQUE
#  index_internal_chat_channel_teams_on_team_id  (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (internal_chat_channel_id => internal_chat_channels.id)
#  fk_rails_...  (team_id => teams.id)
#
class InternalChat::ChannelTeam < ApplicationRecord
  self.table_name = 'internal_chat_channel_teams'

  belongs_to :channel, class_name: 'InternalChat::Channel', foreign_key: :internal_chat_channel_id, inverse_of: :channel_teams
  belongs_to :team

  validates :team_id, uniqueness: { scope: :internal_chat_channel_id }
end
