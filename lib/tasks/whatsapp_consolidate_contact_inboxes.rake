# Backfill task for the live consolidation logic in
# `Whatsapp::IncomingMessageBaseService#reconcile_cloud_contact_inbox_to_canonical`.
#
# Production accounts that received messages BEFORE the consolidation went
# live may already have multiple contact_inboxes for the same contact in
# the same Cloud inbox — one created by an external integration (pencil,
# n8n, CRM) with an off-format source_id, and one created later when the
# patient actually messaged in via Meta. Conversations stay anchored to
# whichever ci was current at the time, so outbound on the older
# conversation keeps targeting the off-format source_id and Meta keeps
# returning 131026 ("Message undeliverable").
#
# This task walks every WhatsApp Cloud inbox, finds contacts with > 1
# contact_inbox in the same inbox, and merges duplicates onto the
# canonical ci (the one whose source_id is the bare digits of the
# contact's phone_number — Meta's canonical wa_id format). Conversations
# from the off-format duplicates are moved onto the survivor, then the
# duplicates are deleted.
#
# Idempotent: re-running on a clean account is a no-op.

# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
def consolidate_contact_inbox_duplicates_for_inbox(inbox)
  contacts_with_duplicates = inbox.contact_inboxes.group(:contact_id).having('COUNT(*) > 1').count
  return 0 if contacts_with_duplicates.empty?

  contacts_with_duplicates.keys.sum do |contact_id|
    contact = Contact.find_by(id: contact_id)
    next 0 if contact.blank? || contact.phone_number.blank?

    canonical_waid = contact.phone_number.delete('+')
    cis = inbox.contact_inboxes.where(contact_id: contact_id).order(:created_at)
    survivor = cis.find_by(source_id: canonical_waid) || cis.first
    survivor.update!(source_id: canonical_waid) if survivor.source_id != canonical_waid

    cis.where.not(id: survivor.id).find_each.sum do |dup|
      moved = dup.conversations.update_all(contact_inbox_id: survivor.id) # rubocop:disable Rails/SkipsModelValidations
      dup.destroy!
      puts "[whatsapp:consolidate] inbox=#{inbox.id} contact=#{contact_id} merged " \
           "ci=#{dup.id} (#{dup.source_id.inspect}) → ci=#{survivor.id} " \
           "(#{survivor.source_id.inspect}), conversations moved: #{moved}"
      1
    end
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity

namespace :whatsapp do
  desc 'Consolidate duplicate contact_inboxes on WhatsApp Cloud inboxes'
  task consolidate_contact_inboxes: :environment do
    merged_total = 0
    inboxes_touched = 0

    Channel::Whatsapp.where(provider: 'whatsapp_cloud').includes(:inbox).find_each do |channel|
      next unless channel.inbox

      merged = consolidate_contact_inbox_duplicates_for_inbox(channel.inbox)
      next if merged.zero?

      inboxes_touched += 1
      merged_total += merged
    end

    puts "Done. Inboxes scanned with duplicates: #{inboxes_touched}. Duplicate contact_inboxes merged: #{merged_total}."
  end
end
