require 'rails_helper'

RSpec.describe ActionCableBroadcastJob do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:members) { ['agent-token'] }
  let(:base_data) { { id: conversation.display_id, account_id: account.id } }

  describe '#perform' do
    context 'when the event is a conversation update' do
      let(:event_name) { 'conversation.updated' }
      let(:data) { base_data.merge(event_metadata: { source: 'reaction_toggle' }) }

      # The job re-fetches `conversation.push_event_data` to drop stale
      # snapshots in race conditions, but transient per-event tags (eg. the
      # `reaction_toggle` source the frontend reads to skip auto-scroll) live
      # only on the original payload — they have to be carried forward.
      it 'preserves event_metadata after refreshing the payload' do
        expect(ActionCable.server).to receive(:broadcast) do |_member, payload|
          expect(payload[:event]).to eq('conversation.updated')
          expect(payload[:data][:event_metadata]).to eq(source: 'reaction_toggle')
          # And the refresh still happened — id comes from the reloaded record.
          expect(payload[:data][:id]).to eq(conversation.display_id)
        end
        described_class.new.perform(members, event_name, data)
      end
    end

    context 'when the event is a conversation update without event_metadata' do
      let(:event_name) { 'conversation.updated' }
      let(:data) { base_data }

      # Regression guard: a missing `event_metadata` must NOT be assigned as `nil`
      # on the refreshed payload. The frontend uses optional chaining today, but
      # locking the absence here protects against a future loosening of the
      # `present?` check on the job side.
      it 'does not inject a nil event_metadata key' do
        expect(ActionCable.server).to receive(:broadcast) do |_member, payload|
          expect(payload[:event]).to eq('conversation.updated')
          expect(payload[:data]).not_to have_key(:event_metadata)
          expect(payload[:data][:id]).to eq(conversation.display_id)
        end
        described_class.new.perform(members, event_name, data)
      end
    end

    context 'when the event is not in the refresh list' do
      let(:event_name) { 'message.created' }
      let(:data) { base_data.merge(event_metadata: { source: 'reaction_toggle' }) }

      it 'broadcasts the original data verbatim' do
        expect(ActionCable.server).to receive(:broadcast) do |member, payload|
          expect(member).to eq('agent-token')
          expect(payload[:event]).to eq('message.created')
          expect(payload[:data]).to eq(data)
        end
        described_class.new.perform(members, event_name, data)
      end
    end
  end
end
