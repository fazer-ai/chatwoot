require 'rails_helper'

# Upstream reaches the contactless case by writing `contact_id: nil`, which the fork's
# `null: false` on conversations refuses (20260422170000). The case is still live, shaped
# differently: `Contact has_many :conversations, dependent: :destroy_async` deletes the contact
# and cleans its conversations up in a job, and no foreign key closes that window. So the id
# stays, the row goes, and the SLA code has to hold up there.
RSpec.describe 'SLA on a conversation whose contact row is gone' do # rubocop:disable RSpec/DescribeClass
  it 'keeps the conversation in AppliedSla.with_sla_applicable_conversation' do
    applied_sla = create(:applied_sla)
    blocked_applied_sla = create(:applied_sla)
    dangling_applied_sla = create(:applied_sla)

    blocked_applied_sla.conversation.contact.update!(blocked: true)
    dangling_applied_sla.conversation.contact.delete

    applicable_sla_ids = AppliedSla.with_sla_applicable_conversation.ids

    expect(applicable_sla_ids).to include(applied_sla.id, dangling_applied_sla.id)
    expect(applicable_sla_ids).not_to include(blocked_applied_sla.id)
  end

  it 'keeps the conversation SLA-applicable' do
    conversation = create(:conversation)
    conversation.contact.delete

    expect(conversation.reload.sla_applicable?).to be true
  end
end
