# == Schema Information
#
# Table name: account_health_scores
#
#  id          :bigint           not null, primary key
#  breakdown   :jsonb            not null
#  captured_on :date             not null
#  score       :integer          not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_account_health_scores_on_account_id                  (account_id)
#  index_account_health_scores_on_account_id_and_captured_on  (account_id,captured_on) UNIQUE
#  index_account_health_scores_on_captured_on                 (captured_on)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class AccountHealthScore < ApplicationRecord
  belongs_to :account

  validates :score, presence: true, numericality: { in: 0..100, only_integer: true }
  validates :captured_on, presence: true, uniqueness: { scope: :account_id }
end
