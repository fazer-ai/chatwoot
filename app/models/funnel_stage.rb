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
#
# Indexes
#
#  index_funnel_stages_on_name      (name) UNIQUE
#  index_funnel_stages_on_position  (position)
#
class FunnelStage < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }
  scope :open_stages, -> { where(closed: false) }
  scope :closed_stages, -> { where(closed: true) }

  def matching_label_for(account)
    account.labels.find_by(title: name)
  end

  def color_for(account)
    matching_label_for(account)&.color
  end
end
