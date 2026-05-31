# == Schema Information
#
# Table name: disparos
#
#  id                          :bigint           not null, primary key
#  audience_filter             :jsonb            not null
#  audience_filter_dsl_version :integer          default(1), not null
#  conversation_status         :integer          default("open"), not null
#  description                 :text
#  mode                        :integer          default("exclusive_cloud"), not null
#  name                        :string           not null
#  status                      :integer          default("draft"), not null
#  template_category           :integer          default("utility"), not null
#  template_name               :string
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  account_id                  :integer          not null
#  created_by_id               :integer
#
# Indexes
#
#  index_disparos_on_account_id_and_status  (account_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#
class Disparo < ApplicationRecord
  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true

  has_many :disparo_inboxes, dependent: :destroy
  has_many :disparo_targets, dependent: :destroy
  has_many :disparo_audience_snapshots, dependent: :destroy

  enum status: { draft: 0, scheduled: 1, running: 2, paused: 3, completed: 4, failed: 5, cancelled: 6 }
  enum mode: { exclusive_cloud: 0 }
  # `_prefix: true` avoids the `Disparo.all` scope colliding with AR's built-in `all`.
  # The reader `#conversation_status` still returns 'open'/'all'.
  enum conversation_status: { open: 0, all: 1 }, _prefix: :status
  # Meta template category — drives the MARKETING cross-template cooldown in the
  # EligibilityEngine. `_prefix: true` keeps `marketing`/`utility` scopes from
  # colliding with other enums.
  enum template_category: { marketing: 0, utility: 1, authentication: 2 }, _prefix: :template

  validates :name, presence: true
end
