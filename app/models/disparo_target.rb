# == Schema Information
#
# Table name: disparo_targets
#
#  id                  :bigint           not null, primary key
#  phone_present       :boolean          default(FALSE), not null
#  primary_skip_reason :string
#  shadow_run          :boolean          default(FALSE), not null
#  skip_reasons        :string           default([]), not null, is an Array
#  state               :integer          default("pending"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  contact_id          :integer          not null
#  conversation_id     :integer          not null
#  disparo_id          :bigint           not null
#  dispatch_id         :uuid             not null
#  inbox_id            :integer
#
# Indexes
#
#  idx_on_disparo_id_conversation_id_contact_id_2b1fdc99ae  (disparo_id,conversation_id,contact_id) UNIQUE
#  index_disparo_targets_on_disparo_id_and_state            (disparo_id,state)
#  index_disparo_targets_on_dispatch_id                     (dispatch_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (disparo_id => disparos.id) ON DELETE => cascade
#
class DisparoTarget < ApplicationRecord
  belongs_to :disparo
  belongs_to :conversation
  belongs_to :contact
  belongs_to :inbox, optional: true

  has_many :disparo_events, dependent: :destroy

  enum state: { pending: 0, queued: 1, skipped: 2, cancelled: 3 }

  validates :conversation_id, uniqueness: { scope: [:disparo_id, :contact_id] }
end
