# A WhatsApp group as the provider describes it. Feeds the group syncer, which keeps the
# group contact, its avatar and its participant list in sync.
class Whatsapp::Session::Model::GroupInfo < Data.define(
  :group, :subject, :description, :owner, :created_at, :participants, :size,
  :announce, :locked, :join_approval, :member_add_mode, :picture_url, :invite_code
)
  include Whatsapp::Session::Model::Serializable

  # A member of a group and the role WhatsApp gave them.
  class Participant < Data.define(:party, :role)
    include Whatsapp::Session::Model::Serializable
    coerce party: Whatsapp::Session::Model::Party
    defaults role: 'member'

    ROLES = %w[member admin superadmin].freeze

    def admin?
      role.in?(%w[admin superadmin])
    end
  end

  coerce group: Whatsapp::Session::Model::Address,
         owner: Whatsapp::Session::Model::Party,
         participants: [Participant]
  defaults announce: false, locked: false, join_approval: false, participants: []

  def admins
    Array(participants).select(&:admin?)
  end
end
