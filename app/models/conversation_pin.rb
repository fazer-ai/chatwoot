# == Schema Information
#
# Table name: conversation_pins
#
#  id              :bigint           not null, primary key
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_conversation_pins_on_account_id                   (account_id)
#  index_conversation_pins_on_conversation_id              (conversation_id)
#  index_conversation_pins_on_user_id_and_conversation_id  (user_id,conversation_id) UNIQUE
#
class ConversationPin < ApplicationRecord
  MAX_PER_USER = 5

  validates :account_id, presence: true
  validates :conversation_id, presence: true
  validates :user_id, presence: true
  validates :user_id, uniqueness: { scope: [:conversation_id] }
  validate :within_limit, on: :create

  belongs_to :account
  belongs_to :conversation
  belongs_to :user

  before_validation :ensure_account_id
  after_create_commit :dispatch_pinned_event
  after_destroy_commit :dispatch_unpinned_event

  private

  def ensure_account_id
    self.account_id = conversation&.account_id
  end

  def within_limit
    return if user_id.blank? || account_id.blank?
    return if self.class.where(user_id: user_id, account_id: account_id).count < MAX_PER_USER

    errors.add(:base, I18n.t('errors.conversation_pins.limit_reached', limit: MAX_PER_USER))
  end

  def dispatch_pinned_event
    dispatch_event(CONVERSATION_PINNED)
  end

  def dispatch_unpinned_event
    dispatch_event(CONVERSATION_UNPINNED)
  end

  # Pass serialized data instead of ActiveRecord objects to avoid DeserializationError when the async
  # EventDispatcherJob runs after the pin (or the conversation it belongs to) has been deleted.
  def dispatch_event(event_name)
    return if conversation.blank? || user.blank?

    Rails.configuration.dispatcher.dispatch(
      event_name,
      Time.zone.now,
      conversation_pin: {
        account_id: account_id,
        user_id: user_id,
        conversation_id: conversation.display_id,
        pinned_at: created_at.to_f
      }
    )
  end
end
