# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::Kanban::BoardRoundRobinService do
  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account) }
  let(:agent1) { create(:user, account: account) }
  let(:agent2) { create(:user, account: account) }
  let(:agent3) { create(:user, account: account) }

  before do
    create(:kanban_board_agent, board: board, agent: agent1)
    create(:kanban_board_agent, board: board, agent: agent2)
    create(:kanban_board_agent, board: board, agent: agent3)
  end

  describe '#available_agent' do
    it 'returns nil when no allowed agent ids are provided' do
      service = described_class.new(board: board)
      expect(service.available_agent(allowed_agent_ids: [])).to be_nil
    end

    it 'returns an agent from the allowed list' do
      service = described_class.new(board: board)
      agent = service.available_agent(allowed_agent_ids: [agent1.id.to_s, agent2.id.to_s])
      expect([agent1, agent2]).to include(agent)
    end

    it 'performs round robin assignment' do
      service = described_class.new(board: board)
      allowed = [agent1.id.to_s, agent2.id.to_s, agent3.id.to_s]

      first_agent = service.available_agent(allowed_agent_ids: allowed)
      second_agent = service.available_agent(allowed_agent_ids: allowed)
      third_agent = service.available_agent(allowed_agent_ids: allowed)

      # After three calls, should cycle back
      fourth_agent = service.available_agent(allowed_agent_ids: allowed)

      expect([first_agent, second_agent, third_agent].uniq.size).to eq(3)
      expect(fourth_agent).to eq(first_agent)
    end

    it 'only returns agents that are in both board and allowed list' do
      service = described_class.new(board: board)
      # Only allow agent1
      result = service.available_agent(allowed_agent_ids: [agent1.id.to_s])
      expect(result).to eq(agent1)
    end

    it 'returns nil when allowed agents are not on the board' do
      other_agent = create(:user, account: account)
      service = described_class.new(board: board)
      result = service.available_agent(allowed_agent_ids: [other_agent.id.to_s])
      expect(result).to be_nil
    end
  end

  describe '#add_agent_to_queue' do
    it 'adds agent to the round robin queue' do
      service = described_class.new(board: board)
      new_agent = create(:user, account: account)

      service.add_agent_to_queue(new_agent.id)

      queue = Redis::Alfred.lrange(service.send(:round_robin_key))
      expect(queue).to include(new_agent.id.to_s)
    end
  end

  describe '#remove_agent_from_queue' do
    it 'removes agent from the round robin queue' do
      service = described_class.new(board: board)
      service.reset_queue

      service.remove_agent_from_queue(agent1.id)

      queue = Redis::Alfred.lrange(service.send(:round_robin_key))
      expect(queue).not_to include(agent1.id.to_s)
    end
  end

  describe '#clear_queue' do
    it 'clears the round robin queue' do
      service = described_class.new(board: board)
      service.reset_queue

      service.clear_queue

      queue = Redis::Alfred.lrange(service.send(:round_robin_key))
      expect(queue).to be_empty
    end
  end

  describe '#reset_queue' do
    it 'resets queue with all board agents' do
      service = described_class.new(board: board)

      service.reset_queue

      queue = Redis::Alfred.lrange(service.send(:round_robin_key))
      expect(queue.map(&:to_i).sort).to eq([agent1.id, agent2.id, agent3.id].sort)
    end
  end
end
