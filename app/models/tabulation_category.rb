class TabulationCategory < ApplicationRecord
  include AccountCacheRevalidator

  belongs_to :account
  has_many :tabulation_subcategories, dependent: :destroy_async
  has_many :tabulation_records, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :account_id, presence: true

  scope :active, -> { where(active: true) }
end
