# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::KanbanListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'John Doe') }
  let(:board) { create(:kanban_board, account: account) }
  let!(:board_step) { create(:kanban_board_step, board: board) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  before do
    allow(account).to receive(:kanban_feature_enabled?).and_return(true)
    create(:kanban_board_inbox, board: board, inbox: inbox)
  end

  describe '#conversation_created' do
    let(:event) { Events::Base.new('conversation.created', Time.zone.now, { conversation: conversation }) }

    context 'when kanban feature is disabled' do
      before do
        allow(account).to receive(:kanban_feature_enabled?).and_return(false)
        board.update!(settings: { 'auto_create_task_for_conversation' => true })
      end

      it 'does not create a task' do
        expect do
          listener.conversation_created(event)
        end.not_to change(FazerAi::Kanban::Task, :count)
      end
    end

    context 'when auto_create_task_for_conversation is enabled' do
      before { board.update!(settings: { 'auto_create_task_for_conversation' => true }) }

      it 'creates a task for the conversation' do
        expect do
          listener.conversation_created(event)
        end.to change(FazerAi::Kanban::Task, :count).by(1)
      end

      it 'assigns the conversation to the task' do
        listener.conversation_created(event)

        task = FazerAi::Kanban::Task.last
        expect(task.conversations).to include(conversation)
      end

      it 'creates task in the first step of the board' do
        listener.conversation_created(event)

        task = FazerAi::Kanban::Task.last
        expect(task.board_step).to eq(board.first_step)
      end

      it 'creates task with proper title using account locale' do
        listener.conversation_created(event)

        task = FazerAi::Kanban::Task.last
        expected_title = "Conversation ##{conversation.display_id} - John Doe"
        expect(task.title).to eq(expected_title)
      end

      it 'uses unknown contact text when contact has no name' do
        contact.update!(name: nil)
        listener.conversation_created(event)

        task = FazerAi::Kanban::Task.last
        expect(task.title).to include('Unknown contact')
      end

      it 'creates task without a creator (automation)' do
        listener.conversation_created(event)

        task = FazerAi::Kanban::Task.last
        expect(task.creator).to be_nil
      end

      it 'displays Automation System as creator name' do
        listener.conversation_created(event)

        task = FazerAi::Kanban::Task.last
        expect(task.creator_display_name).to eq('Automation System')
      end

      context 'when conversation has an assigned agent on the board' do
        let(:agent) { create(:user, account: account) }
        let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, assignee: agent) }

        before { create(:kanban_board_agent, board: board, agent: agent) }

        it 'assigns the agent to the task' do
          listener.conversation_created(event)

          task = FazerAi::Kanban::Task.last
          expect(task.assigned_agents).to include(agent)
        end
      end

      context 'when conversation has an assigned agent not on the board' do
        let(:agent) { create(:user, account: account) }
        let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, assignee: agent) }

        it 'does not assign the agent to the task' do
          listener.conversation_created(event)

          task = FazerAi::Kanban::Task.last
          expect(task.assigned_agents).to be_empty
        end
      end

      context 'when conversation has no assigned agent' do
        it 'does not assign any agent to the task' do
          listener.conversation_created(event)

          task = FazerAi::Kanban::Task.last
          expect(task.assigned_agents).to be_empty
        end
      end
    end

    context 'when auto_create_task_for_conversation is disabled' do
      before { board.update!(settings: { 'auto_create_task_for_conversation' => false }) }

      it 'does not create a task' do
        expect do
          listener.conversation_created(event)
        end.not_to change(FazerAi::Kanban::Task, :count)
      end
    end

    context 'when setting is not present' do
      before { board.update!(settings: {}) }

      it 'does not create a task' do
        expect do
          listener.conversation_created(event)
        end.not_to change(FazerAi::Kanban::Task, :count)
      end
    end

    context 'when conversation inbox is not in board inboxes' do
      let(:other_inbox) { create(:inbox, account: account) }
      let(:conversation) { create(:conversation, account: account, inbox: other_inbox, contact: contact) }

      before { board.update!(settings: { 'auto_create_task_for_conversation' => true }) }

      it 'does not create a task' do
        expect do
          listener.conversation_created(event)
        end.not_to change(FazerAi::Kanban::Task, :count)
      end
    end

    context 'when board has no steps' do
      before do
        board.update!(settings: { 'auto_create_task_for_conversation' => true })
        board.steps.destroy_all
        board.update!(steps_order: [])
      end

      it 'does not create a task' do
        expect do
          listener.conversation_created(event)
        end.not_to change(FazerAi::Kanban::Task, :count)
      end
    end

    context 'when multiple boards have the same inbox' do
      let(:board2) { create(:kanban_board, account: account, settings: { 'auto_create_task_for_conversation' => true }) }
      let!(:board2_step) { create(:kanban_board_step, board: board2) } # rubocop:disable RSpec/LetSetup

      before do
        create(:kanban_board_inbox, board: board2, inbox: inbox)
        board.update!(settings: { 'auto_create_task_for_conversation' => true })
      end

      it 'creates tasks in all boards with the setting enabled' do
        expect do
          listener.conversation_created(event)
        end.to change(FazerAi::Kanban::Task, :count).by(2)
      end
    end

    context 'with pt-BR locale' do
      before do
        account.update!(locale: 'pt_BR')
        board.update!(settings: { 'auto_create_task_for_conversation' => true })
      end

      it 'creates task with proper title using pt-BR locale' do
        listener.conversation_created(event)

        task = FazerAi::Kanban::Task.last
        expected_title = "Conversa ##{conversation.display_id} - John Doe"
        expect(task.title).to eq(expected_title)
      end

      it 'uses pt-BR unknown contact text when contact has no name' do
        contact.update!(name: nil)
        listener.conversation_created(event)

        task = FazerAi::Kanban::Task.last
        expect(task.title).to include('Contato desconhecido')
      end
    end
  end

  describe '#kanban_task_created' do
    let!(:admin) { create(:user, account: account, role: :administrator) }
    let(:agent) { create(:user, account: account) }
    let(:task) { create(:kanban_task, board: board, board_step: board_step, account: account, creator: admin) }
    let(:event) { Events::Base.new('kanban.task.created', Time.zone.now, { task: task }) }

    before do
      create(:kanban_board_agent, board: board, agent: agent)
    end

    context 'when kanban feature is disabled' do
      before do
        allow(account).to receive(:kanban_feature_enabled?).and_return(false)
        board.update!(settings: { 'auto_assign_task_to_agent' => true })
      end

      it 'does not auto-assign agents' do
        allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(
          { agent.id.to_s => 'online' }
        )

        listener.kanban_task_created(event)

        expect(task.reload.assigned_agents).to be_empty
      end
    end

    context 'when auto_assign_task_to_agent is enabled' do
      before { board.update!(settings: { 'auto_assign_task_to_agent' => true }) }

      it 'auto-assigns an online agent to the task' do
        allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(
          { agent.id.to_s => 'online' }
        )

        listener.kanban_task_created(event)

        expect(task.reload.assigned_agents).to include(agent)
      end

      it 'does not assign when no agents are online' do
        allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({})

        listener.kanban_task_created(event)

        expect(task.reload.assigned_agents).to be_empty
      end
    end

    context 'when auto_assign_task_to_agent is disabled' do
      before { board.update!(settings: { 'auto_assign_task_to_agent' => false }) }

      it 'does not assign any agent' do
        allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(
          { agent.id.to_s => 'online' }
        )

        listener.kanban_task_created(event)

        expect(task.reload.assigned_agents).to be_empty
      end
    end

    context 'when task already has assigned agents' do
      let(:existing_agent) { create(:user, account: account) }

      before do
        create(:kanban_board_agent, board: board, agent: existing_agent)
        task.assigned_agents << existing_agent
        board.update!(settings: { 'auto_assign_task_to_agent' => true })
      end

      it 'does not assign additional agents' do
        allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(
          { agent.id.to_s => 'online' }
        )

        expect do
          listener.kanban_task_created(event)
        end.not_to(change { task.reload.assigned_agents.count })
      end
    end
  end

  describe '#kanban_task_updated' do
    let!(:first_step) { board.first_step }
    let!(:completed_step) { create(:kanban_board_step, board: board) }
    let(:task) { create(:kanban_task, account: account, board: board, board_step: first_step) }

    let(:event) do
      Events::Base.new(
        'kanban.task.updated',
        Time.zone.now,
        { task: task, changed_attributes: { 'board_step_id' => [first_step.id, completed_step.id] } }
      )
    end

    context 'when kanban feature is disabled' do
      let(:open_conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: 'open') }

      before do
        allow(account).to receive(:kanban_feature_enabled?).and_return(false)
        board.update!(settings: { 'auto_resolve_conversation_on_task_end' => true })
        task.update!(board_step: completed_step)
        task.conversations << open_conversation
      end

      it 'does not resolve conversations' do
        listener.kanban_task_updated(event)

        expect(open_conversation.reload.status).to eq('open')
      end
    end

    context 'when auto_resolve_conversation_on_task_end is enabled' do
      before { board.update!(settings: { 'auto_resolve_conversation_on_task_end' => true }) }

      context 'when task is moved to completed step' do
        let(:open_conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: 'open') }
        let(:pending_conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: 'pending') }
        let(:resolved_conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: 'resolved') }

        before do
          task.update!(board_step: completed_step)
          task.conversations << open_conversation
          task.conversations << pending_conversation
          task.conversations << resolved_conversation
        end

        it 'resolves open conversations linked to the task' do
          listener.kanban_task_updated(event)

          expect(open_conversation.reload.status).to eq('resolved')
        end

        it 'resolves pending conversations linked to the task' do
          listener.kanban_task_updated(event)

          expect(pending_conversation.reload.status).to eq('resolved')
        end

        it 'does not change already resolved conversations' do
          listener.kanban_task_updated(event)

          expect(resolved_conversation.reload.status).to eq('resolved')
        end

        it 'creates activity message with kanban task info' do
          listener.kanban_task_updated(event)

          expect(Conversations::ActivityMessageJob).to have_been_enqueued.with(
            open_conversation,
            hash_including(
              content: I18n.t(
                'conversations.activity.status.kanban_task_resolved',
                task_title: task.title,
                board_name: board.name
              )
            )
          )
        end
      end

      context 'when task is moved to cancelled step' do
        let!(:cancelled_step) { create(:kanban_board_step, board: board, cancelled: true) }
        let(:open_conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: 'open') }

        let(:event_for_cancelled) do
          Events::Base.new(
            'kanban.task.updated',
            Time.zone.now,
            { task: task, changed_attributes: { 'board_step_id' => [first_step.id, cancelled_step.id] } }
          )
        end

        before do
          task.update!(board_step: cancelled_step)
          task.conversations << open_conversation
        end

        it 'resolves conversations linked to the task' do
          listener.kanban_task_updated(event_for_cancelled)

          expect(open_conversation.reload.status).to eq('resolved')
        end
      end

      context 'when task is moved to a non-completed step' do
        let!(:middle_step) { create(:kanban_board_step, board: board) }
        let(:open_conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: 'open') }

        let(:event_for_middle) do
          Events::Base.new(
            'kanban.task.updated',
            Time.zone.now,
            { task: task, changed_attributes: { 'board_step_id' => [first_step.id, middle_step.id] } }
          )
        end

        before do
          # NOTE: Create an additional step so middle_step is not the last (which would infer completed status)
          create(:kanban_board_step, board: board)
          task.update!(board_step: middle_step)
          task.conversations << open_conversation
        end

        it 'does not resolve conversations' do
          listener.kanban_task_updated(event_for_middle)

          expect(open_conversation.reload.status).to eq('open')
        end
      end

      context 'when board_step_id is not in changed_attributes' do
        let(:event_without_step_change) do
          Events::Base.new(
            'kanban.task.updated',
            Time.zone.now,
            { task: task, changed_attributes: { 'title' => %w[Old New] } }
          )
        end

        let(:open_conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: 'open') }

        before do
          task.update!(board_step: completed_step)
          task.conversations << open_conversation
        end

        it 'does not resolve conversations' do
          listener.kanban_task_updated(event_without_step_change)

          expect(open_conversation.reload.status).to eq('open')
        end
      end
    end

    context 'when auto_resolve_conversation_on_task_end is disabled' do
      let(:open_conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: 'open') }

      before do
        board.update!(settings: { 'auto_resolve_conversation_on_task_end' => false })
        task.update!(board_step: completed_step)
        task.conversations << open_conversation
      end

      it 'does not resolve conversations' do
        listener.kanban_task_updated(event)

        expect(open_conversation.reload.status).to eq('open')
      end
    end

    context 'when changed_attributes is nil' do
      let(:event_without_changes) do
        Events::Base.new(
          'kanban.task.updated',
          Time.zone.now,
          { task: task, changed_attributes: nil }
        )
      end

      it 'does not raise error and does not resolve conversations' do
        expect { listener.kanban_task_updated(event_without_changes) }.not_to raise_error
      end
    end
  end

  describe '#conversation_resolved' do
    let!(:first_step) { board.first_step }
    let!(:completed_step) { create(:kanban_board_step, board: board) }
    let(:task) { create(:kanban_task, board: board, board_step: first_step) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: 'resolved', kanban_task: task) }
    let(:event) { Events::Base.new('conversation.resolved', Time.zone.now, { conversation: conversation }) }

    before do
      board.update!(steps_order: [first_step.id, completed_step.id])
    end

    context 'when kanban feature is disabled' do
      before do
        allow(account).to receive(:kanban_feature_enabled?).and_return(false)
        board.update!(settings: { 'auto_complete_task_on_conversation_resolve' => true })
      end

      it 'does not complete the task' do
        listener.conversation_resolved(event)

        expect(task.reload.board_step).to eq(first_step)
      end
    end

    context 'when auto_complete_task_on_conversation_resolve is enabled' do
      before { board.update!(settings: { 'auto_complete_task_on_conversation_resolve' => true }) }

      it 'moves the task to the completed step' do
        expect(task.board_step).to eq(first_step)

        listener.conversation_resolved(event)

        expect(task.reload.board_step).to eq(completed_step)
      end

      it 'does not change task already in completed step' do
        task.update!(board_step: completed_step)

        expect { listener.conversation_resolved(event) }.not_to(change { task.reload.board_step })
      end

      context 'when task is in cancelled step' do
        let!(:cancelled_step) { create(:kanban_board_step, board: board) }

        before do
          board.update!(steps_order: [first_step.id, cancelled_step.id, completed_step.id])
          cancelled_step.update!(cancelled: true)
          task.update!(board_step: cancelled_step)
        end

        it 'does not move the task to completed step' do
          expect { listener.conversation_resolved(event) }.not_to(change { task.reload.board_step })
          expect(task.reload.board_step).to eq(cancelled_step)
        end
      end

      context 'when conversation has no linked task' do
        let(:conversation_without_task) { create(:conversation, account: account, inbox: inbox, contact: contact, status: 'resolved') }
        let(:event_without_task) { Events::Base.new('conversation.resolved', Time.zone.now, { conversation: conversation_without_task }) }

        it 'does nothing' do
          expect { listener.conversation_resolved(event_without_task) }.not_to raise_error
        end
      end
    end

    context 'when auto_complete_task_on_conversation_resolve is disabled' do
      before { board.update!(settings: { 'auto_complete_task_on_conversation_resolve' => false }) }

      it 'does not move the task' do
        listener.conversation_resolved(event)

        expect(task.reload.board_step).to eq(first_step)
      end
    end

    context 'when board has only one step' do
      it 'does not change task when already in only step' do
        single_step_board = create(:kanban_board, account: account)
        only_step = create(:kanban_board_step, board: single_step_board)
        single_step_task = create(:kanban_task, board: single_step_board, board_step: only_step)
        single_step_conversation = create(
          :conversation, account: account, inbox: inbox, contact: contact, status: 'resolved', kanban_task: single_step_task
        )
        single_step_event = Events::Base.new('conversation.resolved', Time.zone.now, { conversation: single_step_conversation })

        create(:kanban_board_inbox, board: single_step_board, inbox: inbox)
        single_step_board.update!(settings: { 'auto_complete_task_on_conversation_resolve' => true })

        expect { listener.conversation_resolved(single_step_event) }.not_to(change { single_step_task.reload.board_step })
      end
    end
  end

  describe '#conversation_updated' do
    let!(:admin) { create(:user, account: account, role: :administrator) }
    let(:agent) { create(:user, account: account) }
    let(:other_agent) { create(:user, account: account) }
    let(:task) { create(:kanban_task, board: board, board_step: board_step, account: account, creator: admin) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, kanban_task: task) }

    before do
      create(:kanban_board_agent, board: board, agent: agent)
      create(:kanban_board_agent, board: board, agent: other_agent)
    end

    context 'when kanban feature is disabled' do
      let(:event) do
        Events::Base.new(
          'conversation.updated',
          Time.zone.now,
          { conversation: conversation, changed_attributes: { 'assignee_id' => [nil, agent.id] } }
        )
      end

      before do
        allow(account).to receive(:kanban_feature_enabled?).and_return(false)
        board.update!(settings: { 'sync_task_and_conversation_agents' => true })
      end

      it 'does not sync agents to task' do
        listener.conversation_updated(event)

        expect(task.reload.assigned_agents).to be_empty
      end
    end

    context 'when sync_task_and_conversation_agents is enabled' do
      before { board.update!(settings: { 'sync_task_and_conversation_agents' => true }) }

      context 'when agent is assigned to conversation' do
        let(:event) do
          Events::Base.new(
            'conversation.updated',
            Time.zone.now,
            { conversation: conversation, changed_attributes: { 'assignee_id' => [nil, agent.id] } }
          )
        end

        it 'adds the agent to the task' do
          listener.conversation_updated(event)

          expect(task.reload.assigned_agents).to include(agent)
        end

        it 'dispatches task update event' do
          expect(Rails.configuration.dispatcher).to receive(:dispatch).with(
            Events::Types::KANBAN_TASK_UPDATED,
            anything,
            hash_including(task: task)
          ).once
          allow(Rails.configuration.dispatcher).to receive(:dispatch).with(anything, anything, anything)

          listener.conversation_updated(event)
        end

        it 'does not duplicate agent if already assigned to task' do
          task.assigned_agents << agent

          expect { listener.conversation_updated(event) }.not_to(change { task.reload.assigned_agents.count })
        end

        it 'does not dispatch task update event if agent already assigned' do
          task.assigned_agents << agent

          expect(Rails.configuration.dispatcher).not_to receive(:dispatch).with(
            Events::Types::KANBAN_TASK_UPDATED,
            anything,
            anything
          )
          allow(Rails.configuration.dispatcher).to receive(:dispatch).with(anything, anything, anything)

          listener.conversation_updated(event)
        end
      end

      context 'when agent is unassigned from conversation' do
        let(:event) do
          Events::Base.new(
            'conversation.updated',
            Time.zone.now,
            { conversation: conversation, changed_attributes: { 'assignee_id' => [agent.id, nil] } }
          )
        end

        before { task.assigned_agents << agent }

        it 'removes the agent from the task' do
          listener.conversation_updated(event)

          expect(task.reload.assigned_agents).not_to include(agent)
        end

        it 'dispatches task update event' do
          expect(Rails.configuration.dispatcher).to receive(:dispatch).with(
            Events::Types::KANBAN_TASK_UPDATED,
            anything,
            hash_including(task: task)
          ).once
          allow(Rails.configuration.dispatcher).to receive(:dispatch).with(anything, anything, anything)

          listener.conversation_updated(event)
        end
      end

      context 'when agent is reassigned' do
        let(:event) do
          Events::Base.new(
            'conversation.updated',
            Time.zone.now,
            { conversation: conversation, changed_attributes: { 'assignee_id' => [agent.id, other_agent.id] } }
          )
        end

        before { task.assigned_agents << agent }

        it 'removes old agent and adds new agent' do
          listener.conversation_updated(event)

          expect(task.reload.assigned_agents).not_to include(agent)
          expect(task.reload.assigned_agents).to include(other_agent)
        end
      end

      context 'when new agent is not on the board' do
        let(:non_board_agent) { create(:user, account: account) }
        let(:event) do
          Events::Base.new(
            'conversation.updated',
            Time.zone.now,
            { conversation: conversation, changed_attributes: { 'assignee_id' => [nil, non_board_agent.id] } }
          )
        end

        it 'does not add the agent to the task' do
          listener.conversation_updated(event)

          expect(task.reload.assigned_agents).not_to include(non_board_agent)
        end
      end

      context 'when conversation has no linked task' do
        let(:conversation_without_task) { create(:conversation, account: account, inbox: inbox, contact: contact) }
        let(:event) do
          Events::Base.new(
            'conversation.updated',
            Time.zone.now,
            { conversation: conversation_without_task, changed_attributes: { 'assignee_id' => [nil, agent.id] } }
          )
        end

        it 'does nothing' do
          expect { listener.conversation_updated(event) }.not_to raise_error
        end
      end

      context 'when changed_attributes does not include assignee_id' do
        let(:event) do
          Events::Base.new(
            'conversation.updated',
            Time.zone.now,
            { conversation: conversation, changed_attributes: { 'status' => %w[open resolved] } }
          )
        end

        it 'does nothing' do
          expect { listener.conversation_updated(event) }.not_to(change { task.reload.assigned_agents.count })
        end
      end
    end

    context 'when sync_task_and_conversation_agents is disabled' do
      let(:event) do
        Events::Base.new(
          'conversation.updated',
          Time.zone.now,
          { conversation: conversation, changed_attributes: { 'assignee_id' => [nil, agent.id] } }
        )
      end

      before { board.update!(settings: { 'sync_task_and_conversation_agents' => false }) }

      it 'does not sync agents' do
        listener.conversation_updated(event)

        expect(task.reload.assigned_agents).to be_empty
      end
    end
  end
end
