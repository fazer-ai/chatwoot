# == Schema Information
#
# Table name: funnel_stages
#
#  id                   :bigint           not null, primary key
#  active               :boolean          default(TRUE), not null
#  chart_display_name   :string
#  chart_group          :string
#  chart_visible        :boolean          default(TRUE), not null
#  closed               :boolean          default(FALSE), not null
#  color                :string           not null
#  description          :text
#  name                 :string           not null
#  position             :integer          default(0), not null
#  requires_loss_reason :boolean          default(FALSE), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#
# Indexes
#
#  index_funnel_stages_on_name      (name) UNIQUE
#  index_funnel_stages_on_position  (position)
#
class FunnelStage < ApplicationRecord
  has_many :conversations, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :color, presence: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }
  scope :open_stages, -> { where(closed: false) }
  scope :closed_stages, -> { where(closed: true) }
end
