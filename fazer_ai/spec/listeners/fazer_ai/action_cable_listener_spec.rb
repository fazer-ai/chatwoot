# frozen_string_literal: true

require 'rails_helper'

describe ActionCableListener do
  let(:listener) { described_class.instance }

  describe '#kanban_task_created' do
    let(:event_name) { :'kanban.task.created' }
    let(:account) { create(:account) }
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:agent1) { create(:user, account: account, role: :agent) }
    let(:agent2) { create(:user, account: account, role: :agent) }
    let(:board) { create(:kanban_board, account: account) }
    let(:board_step) { create(:kanban_board_step, board: board) }
    let(:task) { create(:kanban_task, board: board, board_step: board_step, creator: admin) }
    let(:event) { Events::Base.new(event_name, Time.zone.now, task: task) }

    before do
      create(:kanban_board_agent, board: board, agent: agent1)
      create(:kanban_board_agent, board: board, agent: agent2)
    end

    it 'broadcasts task to board agents and account admins' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          agent1.pubsub_token,
          agent2.pubsub_token,
          admin.pubsub_token
        ),
        'kanban.task.created',
        task.push_event_data.merge(account_id: account.id)
      )

      listener.kanban_task_created(event)
    end

    context 'when Current.user is set' do
      let(:performer) { create(:user, account: account) }

      before do
        Current.user = performer
      end

      after do
        Current.user = nil
      end

      it 'includes performer in the payload' do
        expect(ActionCableBroadcastJob).to receive(:perform_later).with(
          anything,
          'kanban.task.created',
          task.push_event_data.merge(
            account_id: account.id,
            performer: performer.push_event_data
          )
        )

        listener.kanban_task_created(event)
      end
    end
  end

  describe '#kanban_task_updated' do
    let(:event_name) { :'kanban.task.updated' }
    let(:account) { create(:account) }
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:agent1) { create(:user, account: account, role: :agent) }
    let(:agent2) { create(:user, account: account, role: :agent) }
    let(:board) { create(:kanban_board, account: account) }
    let(:board_step) { create(:kanban_board_step, board: board) }
    let(:task) { create(:kanban_task, board: board, board_step: board_step, creator: admin) }
    let(:event) { Events::Base.new(event_name, Time.zone.now, task: task) }

    before do
      create(:kanban_board_agent, board: board, agent: agent1)
      create(:kanban_board_agent, board: board, agent: agent2)
    end

    it 'broadcasts updated task to board agents and account admins' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          agent1.pubsub_token,
          agent2.pubsub_token,
          admin.pubsub_token
        ),
        'kanban.task.updated',
        task.push_event_data.merge(account_id: account.id)
      )

      listener.kanban_task_updated(event)
    end

    context 'when Current.user is set' do
      let(:performer) { create(:user, account: account) }

      before do
        Current.user = performer
      end

      after do
        Current.user = nil
      end

      it 'includes performer in the payload' do
        expect(ActionCableBroadcastJob).to receive(:perform_later).with(
          anything,
          'kanban.task.updated',
          task.push_event_data.merge(
            account_id: account.id,
            performer: performer.push_event_data
          )
        )

        listener.kanban_task_updated(event)
      end
    end
  end

  describe '#kanban_task_deleted' do
    let(:event_name) { :'kanban.task.deleted' }
    let(:account) { create(:account) }
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:agent1) { create(:user, account: account, role: :agent) }
    let(:agent2) { create(:user, account: account, role: :agent) }
    let(:board) { create(:kanban_board, account: account) }
    let(:board_step) { create(:kanban_board_step, board: board) }
    let(:task) { create(:kanban_task, board: board, board_step: board_step, creator: admin) }
    let(:event) { Events::Base.new(event_name, Time.zone.now, task: task) }

    before do
      create(:kanban_board_agent, board: board, agent: agent1)
      create(:kanban_board_agent, board: board, agent: agent2)
    end

    it 'broadcasts task deletion to board agents and account admins' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          agent1.pubsub_token,
          agent2.pubsub_token,
          admin.pubsub_token
        ),
        'kanban.task.deleted',
        hash_including(
          id: task.id,
          board_id: task.board_id,
          account_id: account.id
        )
      )

      listener.kanban_task_deleted(event)
    end

    context 'when task payload is a Hash' do
      let(:task_hash) { task.push_event_data }
      let(:event) { Events::Base.new(event_name, Time.zone.now, task: task_hash) }

      it 'broadcasts task deletion correctly' do
        expect(ActionCableBroadcastJob).to receive(:perform_later).with(
          a_collection_containing_exactly(
            agent1.pubsub_token,
            agent2.pubsub_token,
            admin.pubsub_token
          ),
          'kanban.task.deleted',
          hash_including(
            id: task.id,
            board_id: task.board_id,
            account_id: account.id
          )
        )

        listener.kanban_task_deleted(event)
      end
    end

    context 'when Current.user is set' do
      let(:performer) { create(:user, account: account) }

      before do
        Current.user = performer
      end

      after do
        Current.user = nil
      end

      it 'includes performer in the payload' do
        expect(ActionCableBroadcastJob).to receive(:perform_later).with(
          anything,
          'kanban.task.deleted',
          hash_including(
            id: task.id,
            board_id: task.board_id,
            account_id: account.id,
            performer: performer.push_event_data
          )
        )

        listener.kanban_task_deleted(event)
      end
    end
  end

  describe '#kanban_step_created' do
    let(:event_name) { :'kanban.step.created' }
    let(:account) { create(:account) }
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:agent1) { create(:user, account: account, role: :agent) }
    let(:agent2) { create(:user, account: account, role: :agent) }
    let(:board) { create(:kanban_board, account: account) }
    let(:board_step) { create(:kanban_board_step, board: board) }
    let(:event) { Events::Base.new(event_name, Time.zone.now, step: board_step) }

    before do
      create(:kanban_board_agent, board: board, agent: agent1)
      create(:kanban_board_agent, board: board, agent: agent2)
    end

    it 'broadcasts created step to board agents and account admins' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          agent1.pubsub_token,
          agent2.pubsub_token,
          admin.pubsub_token
        ),
        'kanban.step.created',
        board_step.push_event_data.merge(account_id: account.id)
      )

      listener.kanban_step_created(event)
    end

    context 'when Current.user is set' do
      let(:performer) { create(:user, account: account) }

      before do
        Current.user = performer
      end

      after do
        Current.user = nil
      end

      it 'includes performer in the payload' do
        expect(ActionCableBroadcastJob).to receive(:perform_later).with(
          anything,
          'kanban.step.created',
          hash_including(
            id: board_step.id,
            board_id: board_step.board_id,
            account_id: account.id,
            performer: performer.push_event_data
          )
        )

        listener.kanban_step_created(event)
      end
    end
  end

  describe '#kanban_step_updated' do
    let(:event_name) { :'kanban.step.updated' }
    let(:account) { create(:account) }
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:agent1) { create(:user, account: account, role: :agent) }
    let(:agent2) { create(:user, account: account, role: :agent) }
    let(:board) { create(:kanban_board, account: account) }
    let(:board_step) { create(:kanban_board_step, board: board) }
    let(:event) { Events::Base.new(event_name, Time.zone.now, step: board_step) }

    before do
      create(:kanban_board_agent, board: board, agent: agent1)
      create(:kanban_board_agent, board: board, agent: agent2)
    end

    it 'broadcasts updated step to board agents and account admins' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          agent1.pubsub_token,
          agent2.pubsub_token,
          admin.pubsub_token
        ),
        'kanban.step.updated',
        board_step.push_event_data.merge(account_id: account.id)
      )

      listener.kanban_step_updated(event)
    end

    context 'when Current.user is set' do
      let(:performer) { create(:user, account: account) }

      before do
        Current.user = performer
      end

      after do
        Current.user = nil
      end

      it 'includes performer in the payload' do
        expect(ActionCableBroadcastJob).to receive(:perform_later).with(
          anything,
          'kanban.step.updated',
          hash_including(
            id: board_step.id,
            board_id: board_step.board_id,
            account_id: account.id,
            performer: performer.push_event_data
          )
        )

        listener.kanban_step_updated(event)
      end
    end
  end

  describe '#kanban_board_updated' do
    let(:event_name) { :'kanban.board.updated' }
    let(:account) { create(:account) }
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:agent1) { create(:user, account: account, role: :agent) }
    let(:agent2) { create(:user, account: account, role: :agent) }
    let(:board) { create(:kanban_board, account: account, steps_order: [1, 2, 3]) }
    let(:event) { Events::Base.new(event_name, Time.zone.now, board: board) }

    before do
      create(:kanban_board_agent, board: board, agent: agent1)
      create(:kanban_board_agent, board: board, agent: agent2)
    end

    it 'broadcasts updated board to board agents and account admins' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          agent1.pubsub_token,
          agent2.pubsub_token,
          admin.pubsub_token
        ),
        'kanban.board.updated',
        board.push_event_data.merge(account_id: account.id)
      )

      listener.kanban_board_updated(event)
    end

    context 'when Current.user is set' do
      let(:performer) { create(:user, account: account) }

      before do
        Current.user = performer
      end

      after do
        Current.user = nil
      end

      it 'includes performer in the payload' do
        expect(ActionCableBroadcastJob).to receive(:perform_later).with(
          anything,
          'kanban.board.updated',
          hash_including(
            id: board.id,
            account_id: account.id,
            performer: performer.push_event_data
          )
        )

        listener.kanban_board_updated(event)
      end
    end
  end
end
