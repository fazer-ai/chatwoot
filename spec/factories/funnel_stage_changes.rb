FactoryBot.define do
  factory :funnel_stage_change do
    transient do
      inbox { account.inboxes.first || create(:inbox, account: account) }
      contact { create(:contact, account: account) }
    end

    account
    contact_id { contact.id }
    inbox_id { inbox.id }
    conversation_id { create(:conversation, account: account, inbox: inbox, contact: contact).id }
    user { nil }
    previous_stage { nil }
    new_stage { 'lead' }
    cycle { 1 }
    source { 'web' }
  end
end
