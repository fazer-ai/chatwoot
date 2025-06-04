class TabulationSubcategory < ApplicationRecord
  include AccountCacheRevalidator

  belongs_to :account
  belongs_to :tabulation_category
  has_many :tabulation_records, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :tabulation_category_id }
  validates :tabulation_category_id, presence: true
  validates :account_id, presence: true

  scope :active, -> { where(active: true) }
end
