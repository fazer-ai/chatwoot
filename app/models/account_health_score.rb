# == Schema Information
#
# Table name: account_health_scores
#
#  id           :bigint           not null, primary key
#  breakdown    :jsonb            not null
#  captured_on  :date             not null
#  score        :integer          not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#
class AccountHealthScore < ApplicationRecord
  belongs_to :account

  validates :score, presence: true, numericality: { in: 0..100, only_integer: true }
  validates :captured_on, presence: true, uniqueness: { scope: :account_id }
end
