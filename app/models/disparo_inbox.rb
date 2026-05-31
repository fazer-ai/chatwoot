# == Schema Information
#
# Table name: disparo_inboxes
#
#  id         :bigint           not null, primary key
#  provider   :integer          default("cloud"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  disparo_id :bigint           not null
#  inbox_id   :integer          not null
#
# Indexes
#
#  index_disparo_inboxes_on_disparo_id_and_inbox_id  (disparo_id,inbox_id) UNIQUE
#  index_disparo_inboxes_on_inbox_id                 (inbox_id)
#
# Foreign Keys
#
#  fk_rails_...  (disparo_id => disparos.id) ON DELETE => cascade
#  fk_rails_...  (inbox_id => inboxes.id)
#
class DisparoInbox < ApplicationRecord
  belongs_to :disparo
  belongs_to :inbox

  enum provider: { cloud: 0 }

  validates :inbox_id, uniqueness: { scope: :disparo_id }
end
