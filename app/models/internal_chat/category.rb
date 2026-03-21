# == Schema Information
#
# Table name: internal_chat_categories
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  position   :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_internal_chat_categories_on_account_id               (account_id)
#  index_internal_chat_categories_on_account_id_and_name      (account_id,name) UNIQUE
#  index_internal_chat_categories_on_account_id_and_position  (account_id,position)
#
class InternalChat::Category < ApplicationRecord
  self.table_name = 'internal_chat_categories'

  belongs_to :account
  has_many :channels, class_name: 'InternalChat::Channel', dependent: :nullify, inverse_of: :category

  validates :name, presence: true
  validates :name, uniqueness: { scope: :account_id }

  scope :ordered, -> { order(:position) }
end

InternalChat::Category.prepend_mod_with('InternalChat::Category')
