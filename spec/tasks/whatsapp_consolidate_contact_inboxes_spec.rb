require 'rails_helper'
require 'rake'

describe 'whatsapp:consolidate_contact_inboxes', type: :task do
  before do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task['whatsapp:consolidate_contact_inboxes'].reenable
  end

  let(:cloud_channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:cloud_inbox) { cloud_channel.inbox }

  it 'merges duplicate cloud contact_inboxes onto the canonical wa_id' do
    contact = create(:contact, account: cloud_inbox.account, phone_number: '+553197516012')
    off_format_ci = create(:contact_inbox, contact: contact, inbox: cloud_inbox,
                                           source_id: "5531997516012-#{cloud_inbox.id}")
    canonical_ci = create(:contact_inbox, contact: contact, inbox: cloud_inbox, source_id: '553197516012')
    legacy_conversation = create(:conversation, account: cloud_inbox.account, inbox: cloud_inbox,
                                                contact: contact, contact_inbox: off_format_ci)

    Rake::Task['whatsapp:consolidate_contact_inboxes'].invoke

    cis = cloud_inbox.contact_inboxes.where(contact_id: contact.id)
    expect(cis.count).to eq(1)
    expect(cis.first.source_id).to eq('553197516012')
    expect(cis.first.id).to eq(canonical_ci.id)
    expect(legacy_conversation.reload.contact_inbox_id).to eq(canonical_ci.id)
  end

  it 'promotes the oldest off-format ci to canonical when no ci already has the canonical source_id' do
    contact = create(:contact, account: cloud_inbox.account, phone_number: '+553197516012')
    older_ci = create(:contact_inbox, contact: contact, inbox: cloud_inbox,
                                      source_id: "5531997516012-#{cloud_inbox.id}",
                                      created_at: 2.days.ago)
    newer_ci = create(:contact_inbox, contact: contact, inbox: cloud_inbox,
                                      source_id: "5531999999999-#{cloud_inbox.id}",
                                      created_at: 1.day.ago)

    Rake::Task['whatsapp:consolidate_contact_inboxes'].invoke

    expect(cloud_inbox.contact_inboxes.where(contact_id: contact.id).count).to eq(1)
    survivor = cloud_inbox.contact_inboxes.find_by(contact_id: contact.id)
    expect(survivor.id).to eq(older_ci.id)
    expect(survivor.source_id).to eq('553197516012')
    expect(ContactInbox.exists?(id: newer_ci.id)).to be(false)
  end

  it 'is a no-op when contact has only one ci' do
    contact = create(:contact, account: cloud_inbox.account, phone_number: '+553197516012')
    ci = create(:contact_inbox, contact: contact, inbox: cloud_inbox, source_id: "5531997516012-#{cloud_inbox.id}")

    Rake::Task['whatsapp:consolidate_contact_inboxes'].invoke

    expect(cloud_inbox.contact_inboxes.where(contact_id: contact.id).pluck(:id)).to eq([ci.id])
    expect(ci.reload.source_id).to eq("5531997516012-#{cloud_inbox.id}")
  end

  it 'skips non-cloud inboxes' do
    baileys_channel = create(:channel_whatsapp, provider: 'baileys', sync_templates: false, validate_provider_config: false)
    baileys_inbox = baileys_channel.inbox
    contact = create(:contact, account: baileys_inbox.account, phone_number: '+553197516012')
    create(:contact_inbox, contact: contact, inbox: baileys_inbox, source_id: "5531997516012-#{baileys_inbox.id}")
    create(:contact_inbox, contact: contact, inbox: baileys_inbox, source_id: '553197516012')

    Rake::Task['whatsapp:consolidate_contact_inboxes'].invoke

    # Baileys inbox left untouched — the live consolidation is Cloud-only,
    # so the backfill should match the same scope.
    expect(baileys_inbox.contact_inboxes.where(contact_id: contact.id).count).to eq(2)
  end
end
