# Resolves the three records a group message needs: the contact that stands for the
# group, the contact of whoever wrote the message, and the membership between them.
#
# The heavy lifting is GroupConversationHandler, the concern every channel shares. It
# is written against abstract extractors, which is what this class supplies from the
# canonical event.
class Whatsapp::Session::Inbound::GroupResolver
  include GroupConversationHandler

  # What a group message handler needs to write the message.
  Result = Data.define(:group_contact_inbox, :group_contact, :sender_contact)

  attr_reader :inbox, :group, :sender, :subject

  def initialize(inbox:, group:, sender: nil, subject: nil)
    @inbox = inbox
    @group = group
    @sender = sender
    @subject = subject
  end

  def perform
    group_contact_inbox, group_contact = find_or_create_group_contact
    sender_contact = resolve_sender
    add_group_member(group_contact, sender_contact) if sender_contact

    Result.new(group_contact_inbox: group_contact_inbox, group_contact: group_contact, sender_contact: sender_contact)
  end

  # The thread of the group, honouring the same reopen rules as a 1:1 conversation.
  #
  # Not `find_or_create_group_conversation`: that one only reuses open and pending rows,
  # so a group whose thread was snoozed, or resolved under `lock_to_single_conversation`,
  # would get a second conversation and split the group in two. It lives in the concern
  # the frozen Baileys layer also uses, so the policy is applied here instead of changed
  # there.
  def conversation_for(group_contact_inbox)
    Whatsapp::Session::Inbound::ConversationFinder.new(
      inbox: inbox, contact: group_contact_inbox.contact, contact_inbox: group_contact_inbox
    ).perform
  end

  # Membership writes live in GroupConversationHandler, which keeps them private
  # because most channels only reach them from their own handler. Group events change
  # membership without a message, so they are exposed here.
  def add_member(group_contact, contact, role: :member)
    add_group_member(group_contact, contact, role: role)
  end

  def remove_member(group_contact, contact)
    remove_group_member(group_contact, contact)
  end

  def update_member_role(group_contact, contact, role)
    update_group_member_role(group_contact, contact, role)
  end

  private

  def resolve_sender
    return if sender.blank?

    Whatsapp::Session::Inbound::ContactResolver.new(inbox: inbox, party: sender)&.perform&.contact
  end

  # Matches what the Baileys layer persists, so a converted inbox keeps addressing the
  # same group contact instead of creating a second one.
  def extract_group_identifier = group.to_jid
  def extract_group_source_id = group.id
  def extract_group_name = subject
  def extract_sender_identifier = sender&.identifier
  def extract_sender_source_id = sender&.source_id
  def extract_sender_name = sender&.name || sender&.phone || sender&.lid
  def extract_sender_phone = sender&.phone_e164
end
