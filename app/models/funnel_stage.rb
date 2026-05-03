# == Schema Information
#
# Table name: funnel_stages
#
#  id          :bigint           not null, primary key
#  active      :boolean          default(TRUE), not null
#  closed      :boolean          default(FALSE), not null
#  description :text
#  name        :string           not null
#  position    :integer          default(0), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_funnel_stages_on_account_id_and_name      (account_id,name) UNIQUE
#  index_funnel_stages_on_account_id_and_position  (account_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class FunnelStage < ApplicationRecord
  belongs_to :account

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }
  scope :open_stages, -> { where(closed: false) }
  scope :closed_stages, -> { where(closed: true) }

  def matching_label
    account.labels.find_by(title: name)
  end

  def color
    matching_label&.color
  end
end
