# Handles consolidation of duplicate contact_inboxes for WhatsApp channels.
# This is needed because:
# 1. When a conversation is first created via UI, a contact_inbox is created with source_id = phone
# 2. When the contact responds, the contact_inbox is updated to source_id = LID
# 3. If the conversation is deleted/resolved and a new one is created, a new contact_inbox
#    with source_id = phone is created (since the existing one has LID)
# 4. This service consolidates these duplicates when a message arrives
class Whatsapp::ContactInboxConsolidationService
  def initialize(inbox:, phone:, lid:, identifier:)
    @inbox = inbox
    @phone = phone
    @lid = lid
    @identifier = identifier
  end

  def perform # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    return unless @phone.present? && @lid.present?
    # If phone and lid are the same, no consolidation needed
    return if @phone == @lid

    phone_contact_inbox = find_phone_contact_inbox
    lid_contact_inbox = find_lid_contact_inbox

    if phone_contact_inbox && lid_contact_inbox && should_consolidate?(phone_contact_inbox, lid_contact_inbox)
      consolidate_contact_inboxes(phone_contact_inbox, lid_contact_inbox)
    elsif phone_contact_inbox && lid_contact_inbox.nil?
      migrate_phone_to_lid(phone_contact_inbox)
    elsif phone_contact_inbox.nil?
      # No phone-based contact_inbox exists, try to find contact by phone and update their contact_inbox
      update_existing_contact_inbox_by_phone
    end
  end

  private

  def find_phone_contact_inbox
    @inbox.contact_inboxes.find_by(source_id: @phone)
  end

  def find_lid_contact_inbox
    @inbox.contact_inboxes.find_by(source_id: @lid)
  end

  def should_consolidate?(phone_contact_inbox, lid_contact_inbox)
    phone_contact_inbox.contact_id == lid_contact_inbox.contact_id
  end

  def consolidate_contact_inboxes(phone_contact_inbox, lid_contact_inbox)
    ActiveRecord::Base.transaction do
      phone_contact_inbox.conversations.find_each do |conversation|
        conversation.update!(contact_inbox_id: lid_contact_inbox.id)
      end

      phone_contact_inbox.destroy!
    end
  end

  def migrate_phone_to_lid(phone_contact_inbox)
    existing_contact = phone_contact_inbox.contact

    return if identifier_conflict?(existing_contact)
    return if phone_conflict?(existing_contact)

    ActiveRecord::Base.transaction do
      phone_contact_inbox.update!(source_id: @lid)
      existing_contact.update!(identifier: @identifier, phone_number: "+#{@phone}")
    end
  end

  # Find contact by phone number and update their contact_inbox source_id to LID
  # This handles the case where contact_inbox has a different source_id (e.g., old format)
  def update_existing_contact_inbox_by_phone
    existing_contact = @inbox.account.contacts.find_by(phone_number: "+#{@phone}")
    return unless existing_contact

    existing_contact_inbox = existing_contact.contact_inboxes.find_by(inbox_id: @inbox.id)
    return unless existing_contact_inbox
    # Don't update if we'd create a duplicate contact_inbox or identifier conflict
    return if find_lid_contact_inbox
    return if identifier_conflict?(existing_contact)

    ActiveRecord::Base.transaction do
      existing_contact.update!(identifier: @identifier)
      existing_contact_inbox.update!(source_id: @lid)
    end
  end

  def identifier_conflict?(existing_contact)
    conflicting = @inbox.account.contacts.find_by(identifier: @identifier)
    conflicting.present? && conflicting.id != existing_contact.id
  end

  def phone_conflict?(existing_contact)
    conflicting = @inbox.account.contacts.find_by(phone_number: "+#{@phone}")
    conflicting.present? && conflicting.id != existing_contact.id
  end
end
