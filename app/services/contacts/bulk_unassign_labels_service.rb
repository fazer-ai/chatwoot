class Contacts::BulkUnassignLabelsService
  def initialize(account:, contact_ids:, labels:)
    @account = account
    @contact_ids = Array(contact_ids)
    @labels = Array(labels).compact_blank
  end

  def perform
    return { success: true, updated_contact_ids: [] } if @contact_ids.blank? || @labels.blank?

    contacts = @account.contacts.where(id: @contact_ids)

    contacts.find_each do |contact|
      remaining_labels = contact.label_list - @labels
      contact.update_labels(remaining_labels) if remaining_labels.size != contact.label_list.size
    end

    { success: true, updated_contact_ids: contacts.pluck(:id) }
  end
end
