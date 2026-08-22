# == Schema Information
#
# Table name: contact_inboxes
#
#  id            :bigint           not null, primary key
#  group_left_at :datetime
#  group_left_at :datetime
#  hmac_verified :boolean          default(FALSE)
#  pubsub_token  :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  contact_id    :bigint
#  inbox_id      :bigint
#  source_id     :text             not null
#
# Indexes
#
#  index_contact_inboxes_on_contact_id              (contact_id)
#  index_contact_inboxes_on_inbox_id                (inbox_id)
#  index_contact_inboxes_on_inbox_id_and_source_id  (inbox_id,source_id) UNIQUE
#  index_contact_inboxes_on_pubsub_token            (pubsub_token) UNIQUE
#  index_contact_inboxes_on_source_id               (source_id)
#

class ContactInbox < ApplicationRecord
  include Pubsubable
  include RegexHelper
  validates :inbox_id, presence: true
  validates :contact_id, presence: true
  validates :source_id, presence: true
  validate :valid_source_id_format?

  belongs_to :contact
  belongs_to :inbox

  has_many :conversations, dependent: :destroy_async

  # contact_inboxes that are not associated with any conversation
  scope :stale_without_conversations, lambda { |time_period|
    left_joins(:conversations)
      .where('contact_inboxes.created_at < ?', time_period)
      .where(conversations: { contact_id: nil })
  }

  def webhook_data
    {
      id: id,
      contact: contact.try(:webhook_data),
      inbox: inbox.webhook_data,
      account: inbox.account.webhook_data,
      current_conversation: current_conversation.try(:webhook_data),
      source_id: source_id
    }
  end

  def current_conversation
    conversations.last
  end

  # Whether this number has left the WhatsApp group this contact is.
  #
  # It lives here rather than on the contact because a group contact is
  # account-scoped (its identifier is the group's own id) while this row is per inbox,
  # so one WhatsApp group can belong to two inboxes of the same account. It used to be a
  # boolean on the shared contact, and one number leaving marked the group as left for
  # every other number in it: the dashboard hid the composer and the group actions on
  # threads that could still send, `sync_group` returned early and stopped refreshing
  # them, and nothing on the inboxes that stayed could clear it, because only a rejoin
  # clears it and they never left.
  def group_left? = group_left_at.present? || legacy_group_left?

  def mark_group_left!
    convert_legacy_group_left!
    return if group_left_at.present?

    update!(group_left_at: Time.current)
  end

  def mark_group_rejoined!
    convert_legacy_group_left!
    return if group_left_at.nil?

    update!(group_left_at: nil)
  end

  private

  # The migration that introduced the column deleted `group_left` from every contact, so
  # a truthy one can only have been written by a worker from the release before it: the
  # rolling deploy window, where a group left through the old code would otherwise be
  # read here as still joined.
  def legacy_group_left? = contact.additional_attributes&.dig('group_left').present?

  # Reading the old boolean is a stopgap; it says "left" without saying where, and it
  # cannot survive the first write of the new shape, because a rejoin here would clear
  # this row and then read the same stale `true` straight back. So the first write
  # converts: every inbox this group is in gets stamped, which is what the boolean meant
  # account wide, and the key goes. Same reading the data migration applies, and it runs
  # at most once per contact.
  def convert_legacy_group_left!
    return unless legacy_group_left?

    contact.with_lock do
      contact.contact_inboxes.where(group_left_at: nil).update_all(group_left_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      contact.update!(additional_attributes: (contact.additional_attributes || {}).except('group_left'))
    end
    reload
  end

  def validate_twilio_source_id
    # https://www.twilio.com/docs/glossary/what-e164#regex-matching-for-e164
    if inbox.channel.medium == 'sms' && !TWILIO_CHANNEL_SMS_REGEX.match?(source_id)
      errors.add(:source_id, "invalid source id for twilio sms inbox. valid Regex #{TWILIO_CHANNEL_SMS_REGEX}")
    elsif inbox.channel.medium == 'whatsapp' && !TWILIO_CHANNEL_WHATSAPP_REGEX.match?(source_id)
      errors.add(:source_id, "invalid source id for twilio whatsapp inbox. valid Regex #{TWILIO_CHANNEL_WHATSAPP_REGEX}")
    end
  end

  def validate_whatsapp_source_id
    return if WHATSAPP_CHANNEL_REGEX.match?(source_id)

    errors.add(:source_id, "invalid source id for whatsapp inbox. valid Regex #{WHATSAPP_CHANNEL_REGEX}")
  end

  def valid_source_id_format?
    validate_twilio_source_id if inbox.channel_type == 'Channel::TwilioSms'
    validate_whatsapp_source_id if inbox.channel_type == 'Channel::Whatsapp'
  end
end
