class TabulationRecord < ApplicationRecord
  belongs_to :account
  belongs_to :conversation
  belongs_to :tabulation_category
  belongs_to :tabulation_subcategory

  enum action_type: { resolved: 0, snoozed: 1, scheduled: 2 }

  validates :conversation_id, :tabulation_category_id, :tabulation_subcategory_id, :account_id, presence: true
end
