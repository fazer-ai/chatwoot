# An announcement group only accepts messages from its admins. Sending anyway would
# leave the message stuck as "sent" while WhatsApp silently dropped it, so it is failed
# here with a reason the agent can read.
class Whatsapp::Session::Outbound::AnnouncementGuard
  attr_reader :message

  def initialize(message)
    @message = message
  end

  # Raises Errors::GroupParticipantNotAllowed when the send must not happen.
  def ensure!
    return unless contact.group_type_group?
    return unless contact.additional_attributes&.dig('announce') == true
    return if inbox_admin?

    message.update_under_lock!(status: :failed, external_error: I18n.t('errors.whatsapp.group_announcement_only'))
    raise Whatsapp::Session::Errors::GroupParticipantNotAllowed, 'only admins can send messages in this group'
  end

  private

  def contact = message.conversation.contact
  def channel = message.inbox.channel

  # Compared through the normalizers rather than by a digit suffix: WhatsApp reports a
  # Brazilian line with or without its ninth digit depending on when it was registered,
  # so the raw digits of one line differ from themselves, while a plain suffix
  # comparison calls two lines from different countries the same one and lets a send
  # through that WhatsApp then drops in silence.
  def inbox_admin?
    return false if channel.phone_number.blank?

    contact.group_memberships.active.where(role: :admin).includes(:contact).any? do |member|
      Whatsapp::Session::PhoneMatch.same_number?(channel.phone_number, member.contact.phone_number)
    end
  end
end
