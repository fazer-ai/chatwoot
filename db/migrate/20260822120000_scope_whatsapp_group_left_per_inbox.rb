# `group_left` was one boolean on a contact every inbox in the group shares, so it could
# only say "left", never "left where". The list it becomes has to be seeded with an
# answer, and the only honest one for a row written under the old rule is "all of them":
# that is what the boolean meant to every reader at the time, so seeding it this way
# leaves every existing group rendering exactly as it does today. The single-inbox case,
# which is nearly all of them, is exact rather than merely unchanged.
class ScopeWhatsappGroupLeftPerInbox < ActiveRecord::Migration[7.1]
  GROUP_CONTACT = 1

  def up
    contact_class.where(group_type: GROUP_CONTACT)
                 .where("additional_attributes ->> 'group_left' = 'true'")
                 .where("additional_attributes -> 'group_left_inbox_ids' IS NULL")
                 .find_each do |contact|
      inbox_ids = contact_inbox_class.where(contact_id: contact.id).distinct.pluck(:inbox_id).compact.sort
      attributes = contact.additional_attributes.merge('group_left_inbox_ids' => inbox_ids)
      contact.update_column(:additional_attributes, attributes) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def down
    contact_class.where(group_type: GROUP_CONTACT)
                 .where("additional_attributes -> 'group_left_inbox_ids' IS NOT NULL")
                 .find_each do |contact|
      left_somewhere = contact.additional_attributes['group_left_inbox_ids'].present?
      attributes = contact.additional_attributes.except('group_left_inbox_ids').merge('group_left' => left_somewhere)
      contact.update_column(:additional_attributes, attributes) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  private

  def contact_class
    @contact_class ||= Class.new(ActiveRecord::Base) do
      self.table_name = 'contacts'
      self.inheritance_column = :_type_disabled
    end
  end

  def contact_inbox_class
    @contact_inbox_class ||= Class.new(ActiveRecord::Base) do
      self.table_name = 'contact_inboxes'
      self.inheritance_column = :_type_disabled
    end
  end
end
