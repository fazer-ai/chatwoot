# == Schema Information
#
# Table name: disparo_audience_snapshots
#
#  id                   :bigint           not null, primary key
#  by_inbox             :jsonb            not null
#  by_skip_reason       :jsonb            not null
#  estimated_cost_cents :integer
#  expires_at           :datetime
#  filter_dsl           :jsonb            not null
#  inbox_ids            :integer          default([]), not null, is an Array
#  total_eligible       :integer          default(0), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  disparo_id           :bigint           not null
#
# Indexes
#
#  index_disparo_audience_snapshots_on_disparo_id  (disparo_id)
#
# Foreign Keys
#
#  fk_rails_...  (disparo_id => disparos.id) ON DELETE => cascade
#
class DisparoAudienceSnapshot < ApplicationRecord
  belongs_to :disparo
end
