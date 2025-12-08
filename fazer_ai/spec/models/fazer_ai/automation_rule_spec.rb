# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::AutomationRule do
  let(:automation_rule) { create(:automation_rule) }

  describe '#conditions_attributes' do
    it 'includes kanban board condition' do
      expect(automation_rule.conditions_attributes).to include('kanban_board_id')
    end

    it 'includes kanban step condition' do
      expect(automation_rule.conditions_attributes).to include('kanban_step_id')
    end

    it 'includes standard automation conditions' do
      expect(automation_rule.conditions_attributes).to include('status')
      expect(automation_rule.conditions_attributes).to include('inbox_id')
      expect(automation_rule.conditions_attributes).to include('assignee_id')
    end
  end

  describe '#actions_attributes' do
    it 'includes move to step action' do
      expect(automation_rule.actions_attributes).to include('move_to_step')
    end

    it 'includes mark completed action' do
      expect(automation_rule.actions_attributes).to include('mark_completed')
    end

    it 'includes mark cancelled action' do
      expect(automation_rule.actions_attributes).to include('mark_cancelled')
    end

    it 'includes standard automation actions' do
      expect(automation_rule.actions_attributes).to include('send_message')
      expect(automation_rule.actions_attributes).to include('assign_agent')
      expect(automation_rule.actions_attributes).to include('send_webhook_event')
    end
  end
end
