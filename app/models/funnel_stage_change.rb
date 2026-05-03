# == Schema Information
#
# Table name: funnel_stage_changes
#
#  id              :uuid             not null, primary key
#  cycle           :integer          default(1), not null
#  new_stage       :string           not null
#  previous_stage  :string
#  reason          :text
#  source          :string
#  created_at      :datetime         not null
#  account_id      :bigint           not null
#  contact_id      :bigint           not null
#  conversation_id :integer          not null
#  inbox_id        :integer          not null
#  user_id         :bigint
#
# Indexes
#
#  index_funnel_stage_changes_on_account_conv_created  (account_id,conversation_id,created_at)
#  index_funnel_stage_changes_on_contact_id            (contact_id)
#  index_funnel_stage_changes_on_conversation_id       (conversation_id)
#  index_funnel_stage_changes_on_user_id               (user_id) WHERE (user_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
class FunnelStageChange < ApplicationRecord
  belongs_to :account
  belongs_to :user, optional: true

  validates :new_stage, presence: true
  validates :cycle, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
end
