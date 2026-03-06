# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::Kanban::Task, type: :model do
  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account) }
  let(:board_step) { create(:kanban_board_step, board: board) }
  let(:task) { build(:kanban_task, board: board, board_step: board_step) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:account) }
    it { is_expected.to validate_presence_of(:board) }
    it { is_expected.to validate_presence_of(:board_step) }
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_length_of(:title).is_at_most(255) }
    it { is_expected.to validate_length_of(:description).is_at_most(5000) }
    it { is_expected.to validate_inclusion_of(:priority).in_array(described_class::PRIORITIES).allow_nil }

    it 'rejects a due date that is before the start date' do
      task.start_date = 2.days.from_now
      task.due_date = 1.day.from_now

      expect(task).not_to be_valid
      expect(task.errors[:due_date]).to include(I18n.t('kanban.tasks.errors.invalid_due_date'))
    end

    it 'rejects an assigned agent not assigned to the board' do
      agent = create(:user, account: account)
      task.assigned_agents << agent

      expect(task).not_to be_valid
      expect(task.errors[:assigned_agents]).to include(I18n.t('kanban.tasks.errors.invalid_assignees'))
    end

    it 'allows an assigned agent assigned to the board' do
      agent = create(:user, account: account)
      create(:kanban_board_agent, board: board, agent: agent)
      task.assigned_agents << agent

      expect(task).to be_valid
    end

    it 'rejects a conversation not from board inbox' do
      other_inbox = create(:inbox, account: account)
      conversation = create(:conversation, account: account, inbox: other_inbox)
      task.conversations << conversation

      expect(task).not_to be_valid
      expect(task.errors[:conversations]).to include(I18n.t('kanban.tasks.errors.invalid_conversations'))
    end

    it 'allows a conversation from board inbox' do
      inbox = create(:inbox, account: account)
      create(:kanban_board_inbox, board: board, inbox: inbox)
      conversation = create(:conversation, account: account, inbox: inbox)
      task.conversations << conversation

      expect(task).to be_valid
    end

    it 'rejects a board step not belonging to the board' do
      other_board = create(:kanban_board, account: account)
      other_step = create(:kanban_board_step, board: other_board)
      task.board_step = other_step

      expect(task).not_to be_valid
      expect(task.errors[:board_step]).to include(I18n.t('kanban.tasks.errors.invalid_board_step'))
    end

    it 'allows a board step belonging to the board' do
      step = create(:kanban_board_step, board: board)
      task.board_step = step

      expect(task).to be_valid
    end

    it 'rejects a contact not belonging to the account' do
      other_account = create(:account)
      contact = create(:contact, account: other_account)
      task.contacts << contact

      expect(task).not_to be_valid
      expect(task.errors[:contacts]).to include(I18n.t('kanban.tasks.errors.invalid_contact_account'))
    end

    it 'allows a contact belonging to the account' do
      contact = create(:contact, account: account)
      task.contacts << contact

      expect(task).to be_valid
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:board) }
    it { is_expected.to belong_to(:board_step) }
    it { is_expected.to have_many(:task_agents).dependent(:destroy) }
    it { is_expected.to have_many(:assigned_agents).through(:task_agents) }
    it { is_expected.to belong_to(:creator).optional }
    it { is_expected.to have_many(:task_contacts).dependent(:destroy) }
    it { is_expected.to have_many(:contacts).through(:task_contacts) }
    it { is_expected.to have_many(:conversations).dependent(:nullify) }
    it { is_expected.to have_many(:audit_events).dependent(:destroy) }
  end

  describe 'labels' do
    let!(:persisted_task) { create(:kanban_task, board: board, board_step: board_step, account: account, creator: create(:user, account: account)) }

    before do
      create(:label, account: account, title: 'priority')
      create(:label, account: account, title: 'bug')
      create(:label, account: account, title: 'feature')
    end

    describe '#update_labels' do
      it 'assigns labels to the task' do
        persisted_task.update_labels(%w[priority bug])

        expect(persisted_task.label_list).to contain_exactly('priority', 'bug')
      end

      it 'replaces existing labels when updating' do
        persisted_task.update_labels(%w[priority])
        persisted_task.update_labels(%w[bug feature])

        expect(persisted_task.label_list).to contain_exactly('bug', 'feature')
      end

      it 'clears labels when given empty array' do
        persisted_task.update_labels(%w[priority bug])
        persisted_task.update_labels([])

        expect(persisted_task.label_list).to be_empty
      end
    end

    describe '#add_labels' do
      it 'adds labels to existing labels' do
        persisted_task.update_labels(%w[priority])
        persisted_task.add_labels(%w[bug])

        expect(persisted_task.label_list).to contain_exactly('priority', 'bug')
      end

      it 'does not duplicate existing labels' do
        persisted_task.update_labels(%w[priority bug])
        persisted_task.add_labels(%w[bug feature])

        expect(persisted_task.label_list).to contain_exactly('priority', 'bug', 'feature')
      end
    end

    describe '#cached_label_list_array' do
      it 'returns an empty array when cached_label_list is nil' do
        persisted_task.cached_label_list = nil

        expect(persisted_task.cached_label_list_array).to eq([])
      end

      it 'returns an empty array when cached_label_list is empty' do
        persisted_task.cached_label_list = ''

        expect(persisted_task.cached_label_list_array).to eq([])
      end

      it 'returns labels as an array' do
        persisted_task.cached_label_list = 'priority, bug, feature'

        expect(persisted_task.cached_label_list_array).to eq(%w[priority bug feature])
      end

      it 'strips whitespace from labels' do
        persisted_task.cached_label_list = '  priority  ,  bug  '

        expect(persisted_task.cached_label_list_array).to eq(%w[priority bug])
      end
    end

    describe '#push_event_data with labels' do
      it 'includes labels in push event data' do
        persisted_task.update_labels(%w[priority bug])
        persisted_task.reload

        event_data = persisted_task.push_event_data

        expect(event_data[:labels]).to contain_exactly('priority', 'bug')
      end

      it 'returns empty array when no labels' do
        event_data = persisted_task.push_event_data

        expect(event_data[:labels]).to eq([])
      end
    end
  end

  describe 'scopes' do
    describe '.ordered' do
      it 'returns tasks ordered by created_at asc' do
        task1 = create(:kanban_task, board: board, board_step: board_step, account: account, creator: create(:user, account: account),
                                     created_at: 2.days.ago)
        task2 = create(:kanban_task, board: board, board_step: board_step, account: account, creator: create(:user, account: account),
                                     created_at: 1.day.ago)
        task3 = create(:kanban_task, board: board, board_step: board_step, account: account, creator: create(:user, account: account),
                                     created_at: 3.days.ago)

        expect(described_class.ordered).to eq([task3, task1, task2])
      end
    end
  end

  describe 'callbacks' do
    describe 'contact-conversation consistency' do
      let(:inbox) { create(:inbox, account: account) }
      let(:contact) { create(:contact, account: account) }
      let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
      let!(:task) { create(:kanban_task, board: board, board_step: board_step, account: account, creator: create(:user, account: account)) }

      before do
        create(:kanban_board_inbox, board: board, inbox: inbox)
      end

      it 'automatically adds contact when conversation is added' do
        task.conversation_ids = [conversation.display_id]
        task.save!

        expect(task.contacts).to include(contact)
      end

      it 'does not duplicate contact if already present' do
        task.contacts << contact
        task.conversation_ids = [conversation.display_id]
        task.save!

        expect(task.contacts.count).to eq(1)
      end
    end

    describe 'step_changed_at tracking' do
      let!(:task) { create(:kanban_task, board: board, board_step: board_step, account: account, creator: create(:user, account: account)) }
      let(:new_step) { create(:kanban_board_step, board: board) }

      it 'sets step_changed_at when board_step_id changes' do
        expect(task.step_changed_at).to be_nil

        freeze_time do
          task.update!(board_step: new_step)
          expect(task.step_changed_at).to eq(Time.current)
        end
      end

      it 'does not change step_changed_at when other attributes change' do
        task.update!(board_step: new_step)
        original_step_changed_at = task.step_changed_at

        travel_to 1.hour.from_now do
          task.update!(title: 'Updated title')
          expect(task.step_changed_at).to eq(original_step_changed_at)
        end
      end

      it 'updates step_changed_at on subsequent step changes' do
        task.update!(board_step: new_step)
        first_change = task.step_changed_at

        another_step = create(:kanban_board_step, board: board)
        travel_to 1.hour.from_now do
          task.update!(board_step: another_step)
          expect(task.step_changed_at).to be > first_change
        end
      end
    end

    describe 'overdue_notified_at reset' do
      let!(:task) do
        create(:kanban_task, board: board, board_step: board_step, account: account,
                             creator: create(:user, account: account), due_date: 1.day.ago)
      end

      before { task.update_column(:overdue_notified_at, 1.hour.ago) } # rubocop:disable Rails/SkipsModelValidations

      it 'resets overdue_notified_at when due_date changes' do
        expect(task.overdue_notified_at).not_to be_nil

        task.update!(due_date: 1.day.from_now)
        expect(task.overdue_notified_at).to be_nil
      end

      it 'does not reset overdue_notified_at when other attributes change' do
        original_notified_at = task.overdue_notified_at

        task.update!(title: 'Updated title')
        expect(task.overdue_notified_at).to eq(original_notified_at)
      end
    end
  end

  describe '#overdue?' do
    it 'returns true if due_date is in the past' do
      task.due_date = 1.day.ago
      expect(task).to be_overdue
    end

    it 'returns false if due_date is in the future' do
      task.due_date = 1.day.from_now
      expect(task).not_to be_overdue
    end

    it 'returns false if due_date is blank' do
      task.due_date = nil
      expect(task).not_to be_overdue
    end
  end

  describe '#due_soon?' do
    it 'returns true if due_date is within 24 hours from now' do
      task.due_date = 12.hours.from_now
      expect(task).to be_due_soon
    end

    it 'returns true if due_date is exactly 24 hours from now' do
      task.due_date = 24.hours.from_now
      expect(task).to be_due_soon
    end

    it 'returns false if due_date is more than 24 hours from now' do
      task.due_date = 25.hours.from_now
      expect(task).not_to be_due_soon
    end

    it 'returns false if due_date is in the past (overdue)' do
      task.due_date = 1.hour.ago
      expect(task).not_to be_due_soon
    end

    it 'returns false if due_date is blank' do
      task.due_date = nil
      expect(task).not_to be_due_soon
    end
  end

  describe '#started?' do
    it 'returns true if start_date is in the past' do
      task.start_date = 1.day.ago
      expect(task).to be_started
    end

    it 'returns true if start_date is now' do
      task.start_date = Time.current
      expect(task).to be_started
    end

    it 'returns false if start_date is in the future' do
      task.start_date = 1.day.from_now
      expect(task).not_to be_started
    end

    it 'returns false if start_date is blank' do
      task.start_date = nil
      expect(task).not_to be_started
    end
  end

  describe '#starting_soon?' do
    it 'returns true if start_date is within 24 hours from now' do
      task.start_date = 12.hours.from_now
      expect(task).to be_starting_soon
    end

    it 'returns true if start_date is exactly 24 hours from now' do
      task.start_date = 24.hours.from_now
      expect(task).to be_starting_soon
    end

    it 'returns false if start_date is more than 24 hours from now' do
      task.start_date = 25.hours.from_now
      expect(task).not_to be_starting_soon
    end

    it 'returns false if start_date is in the past (already started)' do
      task.start_date = 1.hour.ago
      expect(task).not_to be_starting_soon
    end

    it 'returns false if start_date is blank' do
      task.start_date = nil
      expect(task).not_to be_starting_soon
    end
  end

  describe '#date_status' do
    it 'returns overdue when task is overdue' do
      task.due_date = 1.day.ago
      expect(task.date_status).to eq('overdue')
    end

    it 'returns due_soon when task is due soon but not overdue' do
      task.due_date = 12.hours.from_now
      expect(task.date_status).to eq('due_soon')
    end

    it 'returns nil when task has no urgent date status' do
      task.due_date = 2.days.from_now
      expect(task.date_status).to be_nil
    end

    it 'returns nil when due_date is blank' do
      task.due_date = nil
      expect(task.date_status).to be_nil
    end

    it 'prioritizes overdue over due_soon' do
      task.due_date = 1.minute.ago
      expect(task.date_status).to eq('overdue')
    end
  end

  describe '#status' do
    let!(:first_step) { create(:kanban_board_step, board: board) }
    let!(:middle_step) { create(:kanban_board_step, board: board) }
    let!(:last_step) { create(:kanban_board_step, board: board) }

    before do
      board.update!(steps_order: [first_step.id, middle_step.id, last_step.id])
    end

    it 'returns open for tasks in the first step' do
      task = create(:kanban_task, board: board, board_step: first_step, account: account)
      expect(task.status).to eq('open')
    end

    it 'returns open for tasks in a regular middle step' do
      task = create(:kanban_task, board: board, board_step: middle_step, account: account)
      expect(task.status).to eq('open')
    end

    it 'returns completed for tasks in the last step' do
      task = create(:kanban_task, board: board, board_step: last_step, account: account)
      expect(task.status).to eq('completed')
    end

    it 'returns cancelled for tasks in a cancelled step' do
      middle_step.update!(cancelled: true)
      task = create(:kanban_task, board: board, board_step: middle_step, account: account)
      expect(task.status).to eq('cancelled')
    end

    context 'when board has only one step' do
      let(:single_board) { create(:kanban_board, account: account) }
      let!(:single_step) { create(:kanban_board_step, board: single_board) }

      before { single_board.update!(steps_order: [single_step.id]) }

      it 'returns open even for the only step' do
        task = create(:kanban_task, board: single_board, board_step: single_step, account: account)
        expect(task.status).to eq('open')
      end
    end
  end

  describe '#creator_display_name' do
    it 'returns creator name when creator is present' do
      user = create(:user, account: account, name: 'John Doe')
      task.creator = user
      expect(task.creator_display_name).to eq('John Doe')
    end

    it 'returns Automation System when creator is nil' do
      task.creator = nil
      expect(task.creator_display_name).to eq('Automation System')
    end
  end

  describe '#reorder_for_user!' do
    let(:user) { create(:user, account: account) }
    let!(:task1) { create(:kanban_task, board: board, board_step: board_step, account: account, creator: user) }
    let!(:task2) { create(:kanban_task, board: board, board_step: board_step, account: account, creator: user) }
    let!(:task3) { create(:kanban_task, board: board, board_step: board_step, account: account, creator: user) }

    before do
      account_user = user.account_users.find_by(account_id: account.id)
      preference = account_user.kanban_preference || account_user.build_kanban_preference
      preference.update_tasks_order!(board_step.id, [task1.id, task2.id, task3.id])
    end

    it 'moves the task to the specified position' do
      task1.insert_before_task_id = task3.id
      task1.reorder_for_user!(user)

      account_user = user.account_users.find_by(account_id: account.id)
      preference = account_user.kanban_preference
      expect(preference.tasks_order_for(board_step.id)).to eq([task2.id, task1.id, task3.id])
    end

    it 'moves the task to the end if insert_before_task_id is nil' do
      task1.insert_before_task_id = nil
      task1.reorder_for_user!(user)

      account_user = user.account_users.find_by(account_id: account.id)
      preference = account_user.kanban_preference
      expect(preference.tasks_order_for(board_step.id)).to eq([task2.id, task3.id, task1.id])
    end

    it 'moves task to the end if insert_before_task_id is invalid' do
      task1.insert_before_task_id = 0
      task1.reorder_for_user!(user)

      account_user = user.account_users.find_by(account_id: account.id)
      preference = account_user.kanban_preference
      expect(preference.tasks_order_for(board_step.id)).to eq([task2.id, task3.id, task1.id])
    end
  end

  describe 'event dispatching' do
    before do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
    end

    context 'when task is created' do
      it 'dispatches kanban.task.created event' do
        task.save!

        expect(Rails.configuration.dispatcher).to have_received(:dispatch)
          .with(Events::Types::KANBAN_TASK_CREATED, anything, hash_including(task: task))
      end
    end

    context 'when task is updated' do
      it 'dispatches kanban.task.updated event' do
        task.save!
        allow(Rails.configuration.dispatcher).to receive(:dispatch)

        task.update!(title: 'Updated Title')

        expect(Rails.configuration.dispatcher).to have_received(:dispatch)
          .with(Events::Types::KANBAN_TASK_UPDATED, anything, hash_including(task: task))
      end

      it 'includes priority in changed_attributes when priority is updated' do
        task.save!
        allow(Rails.configuration.dispatcher).to receive(:dispatch)

        task.update!(priority: 'high')

        expect(Rails.configuration.dispatcher).to have_received(:dispatch)
          .with(
            Events::Types::KANBAN_TASK_UPDATED,
            anything,
            hash_including(
              task: task,
              changed_attributes: hash_including('priority' => [nil, 'high'])
            )
          )
      end

      it 'accumulates all changes when multiple updates occur in same transaction' do
        task.save!
        allow(Rails.configuration.dispatcher).to receive(:dispatch)

        ActiveRecord::Base.transaction do
          task.update!(priority: 'urgent')
          task.update!(title: 'New Title')
        end

        expect(Rails.configuration.dispatcher).to have_received(:dispatch)
          .with(
            Events::Types::KANBAN_TASK_UPDATED,
            anything,
            hash_including(
              task: task,
              changed_attributes: hash_including(
                'priority' => [nil, 'urgent'],
                'title' => [task.title_before_last_save, 'New Title']
              )
            )
          ).once
      end

      it 'dispatches conversation.updated event for assigned conversations' do
        inbox = create(:inbox, account: account)
        create(:kanban_board_inbox, board: board, inbox: inbox)
        conversation = create(:conversation, account: account, inbox: inbox)

        task.conversation_ids = [conversation.display_id]
        task.save!

        RSpec::Mocks.space.proxy_for(Rails.configuration.dispatcher).reset
        allow(Rails.configuration.dispatcher).to receive(:dispatch)

        task.update!(title: 'Updated Title')

        expect(Rails.configuration.dispatcher).to have_received(:dispatch)
          .with(Conversation::CONVERSATION_UPDATED, anything, hash_including(conversation: conversation))
      end
    end

    context 'when conversations are updated' do
      let(:inbox) { create(:inbox, account: account) }
      let!(:board_inbox) { create(:kanban_board_inbox, board: board, inbox: inbox) } # rubocop:disable RSpec/LetSetup
      let(:conversation) { create(:conversation, account: account, inbox: inbox) }

      it 'dispatches conversation.updated when conversation is assigned to task' do
        task.save!
        allow(Rails.configuration.dispatcher).to receive(:dispatch)

        task.update!(conversation_ids: [conversation.display_id])

        expect(Rails.configuration.dispatcher).to have_received(:dispatch)
          .with(Conversation::CONVERSATION_UPDATED, anything, satisfy { |data| data[:conversation].kanban_task == task })
      end

      it 'dispatches conversation.updated when conversation is unassigned from task' do
        task.save!
        task.update!(conversation_ids: [conversation.display_id])

        RSpec::Mocks.space.proxy_for(Rails.configuration.dispatcher).reset
        allow(Rails.configuration.dispatcher).to receive(:dispatch)

        task.update!(conversation_ids: [])

        expect(Rails.configuration.dispatcher).to have_received(:dispatch)
          .with(Conversation::CONVERSATION_UPDATED, anything, satisfy { |data| data[:conversation].kanban_task.nil? })
      end
    end

    context 'when task is created with conversations' do
      let(:inbox) { create(:inbox, account: account) }
      let!(:board_inbox) { create(:kanban_board_inbox, board: board, inbox: inbox) } # rubocop:disable RSpec/LetSetup
      let(:conversation) { create(:conversation, account: account, inbox: inbox) }

      it 'dispatches conversation.updated event with kanban_task' do
        allow(Rails.configuration.dispatcher).to receive(:dispatch)

        new_task = build(:kanban_task, account: account, board: board, board_step: board_step, creator: task.creator)
        new_task.conversation_ids = [conversation.display_id]
        new_task.save!

        expect(Rails.configuration.dispatcher).to have_received(:dispatch)
          .with(Conversation::CONVERSATION_UPDATED, anything, satisfy { |data| data[:conversation].kanban_task == new_task })
      end
    end

    context 'when task is destroyed' do
      it 'dispatches kanban.task.deleted event' do
        task.save!
        allow(Rails.configuration.dispatcher).to receive(:dispatch)

        task.destroy!

        expect(Rails.configuration.dispatcher).to have_received(:dispatch)
          .with(Events::Types::KANBAN_TASK_DELETED, anything, hash_including(task: hash_including(id: task.id)))
      end

      it 'dispatches conversation.updated event for assigned conversations' do
        inbox = create(:inbox, account: account)
        create(:kanban_board_inbox, board: board, inbox: inbox)
        conversation1 = create(:conversation, account: account, inbox: inbox)
        conversation2 = create(:conversation, account: account, inbox: inbox)

        task.save!
        task.update!(conversation_ids: [conversation1.display_id, conversation2.display_id])
        task.reload

        allow(Rails.configuration.dispatcher).to receive(:dispatch)

        task.destroy!

        expect(Rails.configuration.dispatcher).to have_received(:dispatch)
          .with(Conversation::CONVERSATION_UPDATED, anything, hash_including(conversation: conversation1)).at_least(:once)
        expect(Rails.configuration.dispatcher).to have_received(:dispatch)
          .with(Conversation::CONVERSATION_UPDATED, anything, hash_including(conversation: conversation2)).at_least(:once)
      end
    end
  end

  describe '#push_event_data' do
    let(:inbox) { create(:inbox, account: account) }
    let(:contact) { create(:contact, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

    before do
      create(:kanban_board_inbox, board: board, inbox: inbox)
    end

    it 'returns correct conversations after removing conversation' do
      task.conversation_ids = [conversation.display_id]
      task.save!
      task.reload

      expect(task.conversations.count).to eq(1)
      expect(task.push_event_data[:conversations].count).to eq(1)

      task.conversation_ids = []
      task.save!

      event_data = task.push_event_data

      expect(event_data[:conversation_ids]).to be_empty
      expect(event_data[:conversations]).to be_empty
    end

    it 'returns correct conversations after creating task with conversations' do
      new_task = build(:kanban_task, account: account, board: board, board_step: board_step, creator: task.creator)
      new_task.conversation_ids = [conversation.display_id]

      expect(new_task.conversations).to be_empty

      new_task.save!

      event_data = new_task.push_event_data

      expect(event_data[:conversation_ids]).to contain_exactly(conversation.display_id)
      expect(event_data[:conversations].map { |c| c[:id] }).to contain_exactly(conversation.id)
    end

    context 'with insert_before_task_id' do
      it 'does not include insert_before_task_id when not explicitly set' do
        task.save!
        event_data = task.push_event_data

        expect(event_data).not_to have_key(:insert_before_task_id)
      end

      it 'includes insert_before_task_id when explicitly set to a value' do
        task.save!
        task.insert_before_task_id = 123
        event_data = task.push_event_data

        expect(event_data).to have_key(:insert_before_task_id)
        expect(event_data[:insert_before_task_id]).to eq(123)
      end

      it 'includes insert_before_task_id when explicitly set to nil' do
        task.save!
        task.insert_before_task_id = nil
        event_data = task.push_event_data

        expect(event_data).to have_key(:insert_before_task_id)
        expect(event_data[:insert_before_task_id]).to be_nil
      end
    end

    context 'with contact social profiles' do
      let(:contact_with_social) do
        create(:contact, account: account, additional_attributes: { 'social_profiles' => { 'instagram' => 'handle_test' } })
      end
      let(:conversation_with_social) { create(:conversation, account: account, inbox: inbox, contact: contact_with_social) }

      it 'includes additional_attributes with social_profiles on contacts' do
        create(:kanban_task_contact, task: task, contact: contact_with_social)
        task.reload

        event_data = task.push_event_data
        contact_data = event_data[:contacts].find { |c| c[:id] == contact_with_social.id }

        expect(contact_data[:additional_attributes]).to include('social_profiles' => { 'instagram' => 'handle_test' })
      end

      it 'includes additional_attributes on contact nested in conversations' do
        task.conversation_ids = [conversation_with_social.display_id]
        task.save!

        event_data = task.push_event_data
        contact_data = event_data[:conversations].first[:contact]

        expect(contact_data[:additional_attributes]).to include('social_profiles' => { 'instagram' => 'handle_test' })
      end
    end
  end

  describe '#insert_before_task_id_set?' do
    it 'returns false when insert_before_task_id was never set' do
      expect(task.insert_before_task_id_set?).to be false
    end

    it 'returns true when insert_before_task_id is set to a value' do
      task.insert_before_task_id = 123
      expect(task.insert_before_task_id_set?).to be true
    end

    it 'returns true when insert_before_task_id is set to nil' do
      task.insert_before_task_id = nil
      expect(task.insert_before_task_id_set?).to be true
    end
  end
end
