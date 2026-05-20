require 'rails_helper'

RSpec.describe Conversations::ResolutionJob do
  subject(:job) { described_class.perform_later(account: account) }

  let!(:account) { create(:account) }
  let(:label) { create(:label, title: 'auto-resolved', account: account) }
  let!(:conversation) { create(:conversation, account: account) }

  it 'enqueues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .with(account: account)
      .on_queue('low')
  end

  it 'does nothing when there is no auto resolve duration' do
    described_class.perform_now(account: account)
    expect(conversation.reload.status).to eq('open')
  end

  context 'when auto_resolve_ignore_waiting is true' do
    it 'resolves non-waiting conversations if time of inactivity is more than auto resolve duration' do
      account.update!(auto_resolve_after: 14_400, auto_resolve_ignore_waiting: true) # 10 days in minutes
      conversation.update!(last_activity_at: 13.days.ago, waiting_since: nil)
      described_class.perform_now(account: account)
      expect(conversation.reload.status).to eq('resolved')
    end

    it 'does not resolve waiting conversations even if time of inactivity is more than auto resolve duration' do
      account.update!(auto_resolve_after: 14_400, auto_resolve_ignore_waiting: true) # 10 days in minutes
      conversation.update!(last_activity_at: 13.days.ago, waiting_since: 13.days.ago)
      described_class.perform_now(account: account)
      expect(conversation.reload.status).to eq('open')
    end
  end

  context 'when auto_resolve_ignore_waiting is false' do
    it 'resolves all conversations if time of inactivity is more than auto resolve duration' do
      account.update!(auto_resolve_after: 14_400, auto_resolve_ignore_waiting: false) # 10 days in minutes
      # Create one waiting conversation and one non-waiting conversation
      waiting_conversation = create(:conversation, account: account, last_activity_at: 13.days.ago, waiting_since: 13.days.ago)
      non_waiting_conversation = create(:conversation, account: account, last_activity_at: 13.days.ago, waiting_since: nil)

      described_class.perform_now(account: account)

      expect(waiting_conversation.reload.status).to eq('resolved')
      expect(non_waiting_conversation.reload.status).to eq('resolved')
    end
  end

  it 'adds a label after resolution' do
    account.update!(auto_resolve_label: 'auto-resolved', auto_resolve_after: 14_400)
    conversation = create(:conversation, account: account, last_activity_at: 13.days.ago, waiting_since: 13.days.ago)

    described_class.perform_now(account: account)

    expect(conversation.reload.status).to eq('resolved')
    expect(conversation.reload.label_list).to include('auto-resolved')
  end

  it 'resolves only a limited number of conversations in a single execution' do
    stub_const('Limits::BULK_ACTIONS_LIMIT', 2)
    account.update!(auto_resolve_after: 14_400, auto_resolve_ignore_waiting: false) # 10 days in minutes
    create_list(:conversation, 3, account: account, last_activity_at: 13.days.ago)
    described_class.perform_now(account: account)
    expect(account.conversations.resolved.count).to eq(Limits::BULK_ACTIONS_LIMIT)
  end

  describe 'concurrent execution on the same conversation' do
    # Regression: production saw a single conversation receive 4 copies of the
    # auto-resolve template + 4 "marked resolved by system" activity messages
    # within ~2 seconds. The root cause was 4 ResolutionJob instances each
    # reading `status: :open` from the outer `find_each` query before any of
    # them committed `toggle_status`. The `with_lock` + `status == :open`
    # double-check inside the lock makes the second-through-Nth attempts skip.
    it 'skips the conversation when a concurrent job already resolved the row' do
      account.update!(auto_resolve_after: 14_400, auto_resolve_ignore_waiting: true,
                      auto_resolve_label: 'auto-resolved')
      stale = create(:conversation, account: account, last_activity_at: 13.days.ago, waiting_since: nil)

      # Reload-snapshot the conversation as the outer `find_each` query would
      # — `status: :open` in Ruby memory — and only then flip the DB row to
      # resolved. The job's `with_lock` reloads the record inside the
      # transaction, so after the reload `status` is `:resolved` and our
      # guard short-circuits.
      in_memory = Conversation.find(stale.id)
      expect(in_memory.status).to eq('open')
      # rubocop:disable Rails/SkipsModelValidations
      Conversation.where(id: stale.id).update_all(status: Conversation.statuses[:resolved])
      # rubocop:enable Rails/SkipsModelValidations

      expect do
        described_class.new.send(:resolve_conversation, account, in_memory)
      end.not_to(change { stale.messages.count })

      # Row stays resolved (status didn't flip back via toggle_status) and
      # no auto-resolve label leaked through.
      expect(stale.reload.status).to eq('resolved')
      expect(stale.reload.label_list).not_to include('auto-resolved')
    end
  end
end
