# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::AutomationRules::KanbanConditionsFilterService do
  subject(:service) { described_class.new(automation_rule, task) }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:board) { create(:kanban_board, account: account) }
  let!(:board_inbox) { create(:kanban_board_inbox, board: board, inbox: inbox) } # rubocop:disable RSpec/LetSetup
  let!(:step1) { create(:kanban_board_step, board: board) }
  let!(:step2) { create(:kanban_board_step, board: board) }
  let(:agent) { create(:user, account: account) }
  let!(:board_agent) { create(:kanban_board_agent, board: board, agent: agent) } # rubocop:disable RSpec/LetSetup
  let(:task) do
    create(:kanban_task,
           account: account,
           board: board,
           board_step: step1,
           conversation_ids: [conversation.display_id])
  end

  let(:automation_rule) do
    create(:automation_rule,
           account: account,
           event_name: 'kanban_task_created',
           conditions: conditions,
           actions: [{ action_name: 'assign_agent', action_params: [agent.id] }])
  end

  describe '#perform' do
    context 'with board condition' do
      let(:conditions) do
        [{ attribute_key: 'kanban_board_id', filter_operator: 'equal_to', values: [board.id], query_operator: nil }]
      end

      it 'returns true when board matches' do
        expect(service.perform).to be(true)
      end

      context 'when board does not match' do
        let(:other_board) { create(:kanban_board, account: account) }
        let(:conditions) do
          [{ attribute_key: 'kanban_board_id', filter_operator: 'equal_to', values: [other_board.id], query_operator: nil }]
        end

        it 'returns false' do
          expect(service.perform).to be(false)
        end
      end

      context 'with not_equal_to operator' do
        let(:other_board) { create(:kanban_board, account: account) }
        let(:conditions) do
          [{ attribute_key: 'kanban_board_id', filter_operator: 'not_equal_to', values: [other_board.id], query_operator: nil }]
        end

        it 'returns true when board is different' do
          expect(service.perform).to be(true)
        end
      end
    end

    context 'with step condition' do
      let(:conditions) do
        [{ attribute_key: 'kanban_step_id', filter_operator: 'equal_to', values: [step1.id], query_operator: nil }]
      end

      it 'returns true when step matches' do
        expect(service.perform).to be(true)
      end

      context 'when step does not match' do
        let(:conditions) do
          [{ attribute_key: 'kanban_step_id', filter_operator: 'equal_to', values: [step2.id], query_operator: nil }]
        end

        it 'returns false' do
          expect(service.perform).to be(false)
        end
      end
    end

    context 'with assignee condition' do
      before do
        task.task_agents.create!(agent: agent)
        task.reload
      end

      let(:conditions) do
        [{ attribute_key: 'assignee_id', filter_operator: 'equal_to', values: [agent.id], query_operator: nil }]
      end

      it 'returns true when agent is assigned' do
        expect(service.perform).to be(true)
      end

      context 'with is_present operator' do
        let(:conditions) do
          [{ attribute_key: 'assignee_id', filter_operator: 'is_present', values: [], query_operator: nil }]
        end

        it 'returns true when task has agents' do
          expect(service.perform).to be(true)
        end
      end

      context 'with is_not_present operator and no agents' do
        let(:conditions) do
          [{ attribute_key: 'assignee_id', filter_operator: 'is_not_present', values: [], query_operator: nil }]
        end

        before do
          task.task_agents.destroy_all
          task.reload
        end

        it 'returns true when task has no agents' do
          expect(service.perform).to be(true)
        end
      end
    end

    context 'with inbox condition' do
      let(:conditions) do
        [{ attribute_key: 'inbox_id', filter_operator: 'equal_to', values: [inbox.id], query_operator: nil }]
      end

      it 'returns true when conversation inbox matches' do
        expect(service.perform).to be(true)
      end

      context 'when inbox does not match' do
        let(:other_inbox) { create(:inbox, account: account) }
        let(:conditions) do
          [{ attribute_key: 'inbox_id', filter_operator: 'equal_to', values: [other_inbox.id], query_operator: nil }]
        end

        it 'returns false' do
          expect(service.perform).to be(false)
        end
      end
    end

    context 'with priority condition' do
      let(:conditions) do
        [{ attribute_key: 'priority', filter_operator: 'equal_to', values: [nil], query_operator: nil }]
      end

      it 'returns true when priority matches' do
        expect(service.perform).to be(true)
      end

      context 'when priority does not match' do
        let(:conditions) do
          [{ attribute_key: 'priority', filter_operator: 'equal_to', values: ['urgent'], query_operator: nil }]
        end

        it 'returns false' do
          expect(service.perform).to be(false)
        end
      end
    end

    context 'with multiple conditions' do
      let(:conditions) do
        [
          { attribute_key: 'kanban_board_id', filter_operator: 'equal_to', values: [board.id], query_operator: 'and' },
          { attribute_key: 'priority', filter_operator: 'equal_to', values: [nil], query_operator: nil }
        ]
      end

      it 'returns true when all conditions match' do
        expect(service.perform).to be(true)
      end

      context 'when one condition fails' do
        let(:conditions) do
          [
            { attribute_key: 'kanban_board_id', filter_operator: 'equal_to', values: [board.id], query_operator: 'and' },
            { attribute_key: 'priority', filter_operator: 'equal_to', values: ['urgent'], query_operator: nil }
          ]
        end

        it 'returns false' do
          expect(service.perform).to be(false)
        end
      end
    end

    context 'when rule is inactive' do
      before { automation_rule.update!(active: false) }

      let(:conditions) do
        [{ attribute_key: 'kanban_board_id', filter_operator: 'equal_to', values: [board.id], query_operator: nil }]
      end

      it 'returns false' do
        expect(service.perform).to be(false)
      end
    end

    context 'when rule belongs to different account' do
      let(:other_account) { create(:account) }
      let(:automation_rule) do
        create(:automation_rule,
               account: other_account,
               event_name: 'kanban_task_created',
               conditions: [{ attribute_key: 'kanban_board_id', filter_operator: 'equal_to', values: [board.id], query_operator: nil }],
               actions: [])
      end

      it 'returns false' do
        expect(service.perform).to be(false)
      end
    end
  end
end
