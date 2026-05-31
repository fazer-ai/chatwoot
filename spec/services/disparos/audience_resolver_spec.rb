require 'rails_helper'

describe Disparos::AudienceResolver do
  subject(:resolver) { described_class.new(account: account, filter: filter, inbox_ids: inbox_ids) }

  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let(:inbox_ids) { [inbox.id] }

  def conversation_in_step(step, **attrs)
    create(:conversation, account: account, inbox: inbox, custom_attributes: { 'kanban_step' => step }, **attrs)
  end

  describe '#perform' do
    context 'when filtering by kanban_steps' do
      let(:filter) { { kanban_steps: %w[3 5] } }

      it 'returns conversations whose kanban_step is in the requested list' do
        matching = conversation_in_step('3')
        also_matching = conversation_in_step('5')
        conversation_in_step('1') # different step

        expect(resolver.perform.pluck(:id)).to contain_exactly(matching.id, also_matching.id)
      end

      it 'does not return conversations in a different step' do
        other = conversation_in_step('9')

        expect(resolver.perform.pluck(:id)).not_to include(other.id)
      end

      it 'matches numeric and string stage values as text (->> extracts text)' do
        matching = conversation_in_step('3')

        result = described_class.new(account: account, filter: { kanban_steps: [3, 5] }, inbox_ids: inbox_ids).perform
        expect(result.pluck(:id)).to include(matching.id)
      end
    end

    context 'when filtering by label' do
      let(:filter) { { label: ['vip'] } }

      it 'returns conversations carrying a requested label' do
        labeled = create(:conversation, account: account, inbox: inbox, label_list: ['vip'])
        create(:conversation, account: account, inbox: inbox, label_list: ['regular'])

        expect(resolver.perform.pluck(:id)).to contain_exactly(labeled.id)
      end

      it 'does not return conversations without a requested label when label filter is active' do
        unlabeled = create(:conversation, account: account, inbox: inbox)

        expect(resolver.perform.pluck(:id)).not_to include(unlabeled.id)
      end

      it 'returns each conversation exactly once even when it carries multiple requested labels (grain)' do
        multi = create(:conversation, account: account, inbox: inbox, label_list: %w[vip gold])

        result_ids = described_class.new(account: account, filter: { label: %w[vip gold] }, inbox_ids: inbox_ids).perform.pluck(:id)

        expect(result_ids).to eq([multi.id])
        expect(result_ids.count(multi.id)).to eq(1)
      end
    end

    context 'when filtering by kanban_steps AND label (combined semantics)' do
      let(:filter) { { kanban_steps: %w[3], label: ['vip'] } }

      it 'returns only conversations matching the step AND carrying a label' do
        both = conversation_in_step('3', label_list: ['vip'])
        conversation_in_step('3', label_list: ['regular']) # right step, wrong label
        conversation_in_step('1', label_list: ['vip']) # right label, wrong step

        expect(resolver.perform.pluck(:id)).to contain_exactly(both.id)
      end
    end

    context 'with account isolation' do
      let(:filter) { { kanban_steps: %w[3] } }

      it 'never returns conversations from another account' do
        other_account = create(:account)
        other_inbox = create(:inbox, account: other_account)
        create(:conversation, account: other_account, inbox: other_inbox, custom_attributes: { 'kanban_step' => '3' })

        expect(resolver.perform).to be_empty
      end
    end

    context 'with grain (conversation_id, contact_id)' do
      let(:filter) { { kanban_steps: %w[3] } }

      it 'returns one row per matching conversation exposing conversation_id and contact_id with contact preloaded' do
        conversation = conversation_in_step('3')

        result = resolver.perform

        expect(result.size).to eq(1)
        row = result.first
        expect(row.id).to eq(conversation.id)
        expect(row.contact_id).to eq(conversation.contact_id)
        expect(result.includes_values).to include(:contact)
      end
    end

    # AC45: the resolver is NOT the enforcement point for eligibility. A
    # candidate matching the stage filter is returned even with no phone and
    # even when it carries the agente-off-permanente label.
    context 'when honouring AC45 (does not apply system exclusions)' do
      let(:filter) { { kanban_steps: %w[3] } }

      it 'still returns a matching conversation whose contact has no phone' do
        contact = create(:contact, account: account, phone_number: nil)
        conversation = conversation_in_step('3', contact: contact)

        expect(resolver.perform.pluck(:id)).to include(conversation.id)
      end

      it 'still returns a matching conversation carrying the agente-off-permanente label' do
        conversation = conversation_in_step('3', label_list: ['agente-off-permanente'])

        expect(resolver.perform.pluck(:id)).to include(conversation.id)
      end
    end

    context 'with an empty/invalid filter (neither kanban_steps nor label)' do
      it 'raises InvalidAudienceFilter when both are absent' do
        expect { described_class.new(account: account, filter: {}, inbox_ids: inbox_ids).perform }
          .to raise_error(CustomExceptions::Disparos::InvalidAudienceFilter)
      end

      it 'raises InvalidAudienceFilter when both are blank arrays' do
        expect { described_class.new(account: account, filter: { kanban_steps: [], label: [] }, inbox_ids: inbox_ids).perform }
          .to raise_error(CustomExceptions::Disparos::InvalidAudienceFilter)
      end
    end

    context 'with blank inbox_ids (no selected inbox)' do
      let(:filter) { { kanban_steps: %w[3] } }

      it 'raises InvalidAudienceFilter when inbox_ids is empty' do
        expect { described_class.new(account: account, filter: filter, inbox_ids: []).perform }
          .to raise_error(CustomExceptions::Disparos::InvalidAudienceFilter)
      end
    end

    # wf15 reconciliation: the operator-SELECTED inbox(es) scope the audience IN
    # the resolver (not the engine). A matching conversation on an inbox that is
    # NOT in the selected set never appears in the audience.
    context 'when scoping by selected inboxes' do
      let(:filter) { { kanban_steps: %w[3] } }
      let!(:other_inbox) { create(:inbox, account: account) }

      it 'includes a matching conversation on a selected inbox and excludes one on an unselected inbox' do
        selected = conversation_in_step('3') # on `inbox` (selected)
        unselected = create(:conversation, account: account, inbox: other_inbox, custom_attributes: { 'kanban_step' => '3' })

        result_ids = described_class.new(account: account, filter: filter, inbox_ids: [inbox.id]).perform.pluck(:id)

        expect(result_ids).to include(selected.id)
        expect(result_ids).not_to include(unselected.id)
      end
    end

    # wf15 reconciliation: conversation STATUS gate. 'open' keeps only open
    # conversations; 'all' applies no status filter.
    context 'when filtering by conversation_status' do
      let(:filter) { { kanban_steps: %w[3] } }

      it "with 'open' excludes a non-open (resolved) conversation that otherwise matches" do
        open_convo = conversation_in_step('3') # status defaults to open in the factory
        resolved_convo = conversation_in_step('3', status: :resolved)

        result_ids = described_class.new(account: account, filter: filter, inbox_ids: inbox_ids, conversation_status: :open).perform.pluck(:id)

        expect(result_ids).to include(open_convo.id)
        expect(result_ids).not_to include(resolved_convo.id)
      end

      it "with 'all' includes the resolved conversation alongside the open one" do
        open_convo = conversation_in_step('3')
        resolved_convo = conversation_in_step('3', status: :resolved)

        result_ids = described_class.new(account: account, filter: filter, inbox_ids: inbox_ids, conversation_status: :all).perform.pluck(:id)

        expect(result_ids).to contain_exactly(open_convo.id, resolved_convo.id)
      end
    end
  end
end
