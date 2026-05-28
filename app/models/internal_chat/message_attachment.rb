# == Schema Information
#
# Table name: internal_chat_message_attachments
#
#  id                       :bigint           not null, primary key
#  extension                :string
#  external_url             :string
#  file_type                :integer          default("image"), not null
#  meta                     :jsonb
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#  internal_chat_message_id :bigint           not null
#
# Indexes
#
#  idx_ic_msg_attachments_message                         (internal_chat_message_id)
#  index_internal_chat_message_attachments_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (internal_chat_message_id => internal_chat_messages.id)
#
class InternalChat::MessageAttachment < ApplicationRecord
  self.table_name = 'internal_chat_message_attachments'

  belongs_to :account
  belongs_to :message, class_name: 'InternalChat::Message', foreign_key: :internal_chat_message_id, inverse_of: :attachments

  has_one_attached :file

  validates :file, presence: true

  enum :file_type, { image: 0, audio: 1, video: 2, file: 3 }
end

InternalChat::MessageAttachment.prepend_mod_with('InternalChat::MessageAttachment')
