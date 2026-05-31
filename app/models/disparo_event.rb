# == Schema Information
#
# Table name: disparo_events
#
#  id                :bigint           not null, primary key
#  event_type        :integer          not null
#  payload           :jsonb            not null
#  created_at        :datetime         not null
#  disparo_target_id :bigint           not null
#
# Indexes
#
#  index_disparo_events_on_disparo_target_id  (disparo_target_id)
#  index_disparo_events_on_event_type         (event_type)
#
# Foreign Keys
#
#  fk_rails_...  (disparo_target_id => disparo_targets.id) ON DELETE => cascade
#
class DisparoEvent < ApplicationRecord
  belongs_to :disparo_target

  enum event_type: {
    queued: 0,
    sending: 1,
    sent: 2,
    delivered: 3,
    read: 4,
    replied: 5,
    failed: 6,
    skipped: 7,
    cancelled: 8,
    retried: 9,
    reconciled_unknown: 10
  }
end
