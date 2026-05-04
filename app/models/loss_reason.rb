# == Schema Information
#
# Table name: loss_reasons
#
#  id         :bigint           not null, primary key
#  active     :boolean          default(TRUE), not null
#  name       :string           not null
#  position   :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_loss_reasons_on_name      (name) UNIQUE
#  index_loss_reasons_on_position  (position)
#
class LossReason < ApplicationRecord
  has_many :funnel_stage_changes, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }
end
