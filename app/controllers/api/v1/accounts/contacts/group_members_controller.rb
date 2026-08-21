class Api::V1::Accounts::Contacts::GroupMembersController < Api::V1::Accounts::Contacts::BaseController
  DEFAULT_PER_PAGE = 10

  before_action :ensure_group_contact, only: %i[create update destroy]

  def index
    authorize @contact, :show?

    base_query = GroupMember.active
                            .where(group_contact: @contact)
                            .includes(:contact)

    @total_count = base_query.count
    @page = [(params[:page] || 1).to_i, 1].max
    @per_page = (params[:per_page] || DEFAULT_PER_PAGE).to_i.clamp(1, 100)
    @inbox_phone_number = inbox_phone_number
    @own_member = own_member_matchable? ? find_own_member : nil
    @is_inbox_admin = @own_member&.role == 'admin'

    paginated = base_query.order(role: :desc, id: :asc)
                          .offset((@page - 1) * @per_page)
                          .limit(@per_page)

    @group_members = pin_own_member_on_first_page(paginated)
  end

  def create
    authorize @contact, :update?
    participants = create_params[:participants]
    return render json: { error: 'participants_required' }, status: :unprocessable_entity if participants.blank?

    channel.update_group_participants(@contact.identifier, format_participants(participants), 'add')
    add_group_members(participants)
    head :ok
  rescue Whatsapp::Session::Errors::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    authorize @contact, :update?
    role = update_params[:role]
    return render json: { error: 'invalid_role' }, status: :unprocessable_entity unless %w[admin member].include?(role)

    member = group_members.find(params[:member_id])
    action = role == 'admin' ? 'promote' : 'demote'
    channel.update_group_participants(@contact.identifier, [jid_for_member(member)], action)
    member.update!(role: role)
    head :ok
  rescue Whatsapp::Session::Errors::GroupParticipantNotAllowed
    render json: { error: 'group_creator_not_modifiable' }, status: :unprocessable_entity
  rescue Whatsapp::Session::Errors::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    authorize @contact, :update?

    member = group_members.find(params[:id])
    channel.update_group_participants(@contact.identifier, [jid_for_member(member)], 'remove')
    member.update!(is_active: false)
    head :ok
  rescue Whatsapp::Session::Errors::GroupParticipantNotAllowed
    render json: { error: 'group_creator_not_modifiable' }, status: :unprocessable_entity
  rescue Whatsapp::Session::Errors::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def ensure_group_contact
    return if @contact.group_type_group? && @contact.identifier.present?

    render json: { error: 'Contact is not a valid group' }, status: :unprocessable_entity
  end

  def group_members
    GroupMember.where(group_contact: @contact)
  end

  def create_params
    params.permit(participants: [])
  end

  def update_params
    params.permit(:role)
  end

  def channel
    @channel ||= @contact.group_channel
  end

  def inbox_phone_number
    channel&.phone_number
  end

  # The same rule Whatsapp::Session::Owner applies on the server: the connected account is
  # matched by its phone, and by its LID when the provider gave one. A native or Uazapi
  # roster can name that account by LID alone, and a contact known that way carries no
  # phone number at all, so a phone-only match reports the inbox as an ordinary member of
  # a group it administers -- which is what the dashboard reads to decide whether replies
  # are allowed in an announcement-only group.
  def own_member_identifier
    return @own_member_identifier if defined?(@own_member_identifier)

    lid = channel&.provider_connection.to_h['lid'].presence
    @own_member_identifier = lid && "#{lid}@lid"
  end

  def own_member_matchable?
    @inbox_phone_number.present? || own_member_identifier.present?
  end

  def pin_own_member_on_first_page(paginated)
    return paginated unless @page == 1

    ids = paginated.pluck(:id)
    own = @own_member
    return paginated if own.blank? || ids.include?(own.id)

    # Prepend own member; drop the last one so total per-page stays consistent
    [own] + paginated.where.not(id: own.id).limit(@per_page - 1).to_a
  end

  # A blank phone must not match the contacts that have none, and a nil identifier needs
  # no guard of its own: `contacts.identifier = NULL` is never true. Spelling that guard
  # out is in fact what Postgres refuses -- a bare parameter next to `IS NOT NULL` has no
  # type to infer, and the query dies with IndeterminateDatatype.
  OWN_MEMBER_SQL = <<~SQL.squish.freeze
    (:phone <> '' AND (
      REPLACE(contacts.phone_number, '+', '') = :phone
      OR RIGHT(REPLACE(contacts.phone_number, '+', ''), 8) = RIGHT(:phone, 8)
    ))
    OR contacts.identifier = :identifier
  SQL

  def find_own_member
    GroupMember.active
               .where(group_contact: @contact)
               .joins(:contact)
               .where(OWN_MEMBER_SQL, phone: @inbox_phone_number.to_s.delete('+'), identifier: own_member_identifier)
               .includes(:contact)
               .first
  end

  def format_participants(phone_numbers)
    Array(phone_numbers).map { |phone| "#{phone.to_s.delete('+')}@s.whatsapp.net" }
  end

  # A group roster can name a participant WhatsApp only ever gave a LID for, and those
  # contacts have no phone number at all: building a phone JID from one produced
  # `@s.whatsapp.net`, which no provider accepts, so the member could not be promoted,
  # demoted or removed. Address is where the rule for which id a contact is reachable by
  # already lives.
  def jid_for_member(member)
    address = Whatsapp::Session::Model::Address.for_contact(member.contact)
    raise Whatsapp::Session::Errors::InvalidPayload, 'group member has no WhatsApp address' if address.nil?

    address.to_jid
  end

  def add_group_members(phone_numbers)
    inbox = @contact.contact_inboxes.first&.inbox
    Array(phone_numbers).each do |phone|
      normalized = normalize_phone(phone)
      next if normalized.blank?

      contact_inbox = ::ContactInboxWithContactBuilder.new(
        source_id: normalized.delete('+'),
        inbox: inbox,
        contact_attributes: { name: normalized, phone_number: normalized }
      ).perform
      next if contact_inbox.blank?

      member = GroupMember.find_or_initialize_by(group_contact: @contact, contact: contact_inbox.contact)
      member.update!(role: :member, is_active: true) unless member.persisted? && member.is_active?
    end
  end

  def normalize_phone(phone)
    cleaned = phone.to_s.strip
    return nil if cleaned.blank?

    cleaned.start_with?('+') ? cleaned : "+#{cleaned}"
  end
end
