import { describe, it, beforeEach, expect, vi } from 'vitest';
import ActionCableConnector from '../actionCable';

vi.mock('shared/helpers/mitt', () => ({
  emitter: {
    emit: vi.fn(),
  },
}));

vi.mock('dashboard/composables/useImpersonation', () => ({
  useImpersonation: () => ({
    isImpersonating: { value: false },
  }),
}));

global.chatwootConfig = {
  websocketURL: 'wss://test.chatwoot.com',
};

describe('ActionCableConnector - Copilot Tests', () => {
  let store;
  let actionCable;
  let mockDispatch;

  beforeEach(() => {
    vi.clearAllMocks();
    mockDispatch = vi.fn();
    store = {
      $store: {
        dispatch: mockDispatch,
        getters: {
          getCurrentAccountId: 1,
        },
      },
    };

    actionCable = ActionCableConnector.init(store.$store, 'test-token');
  });
  describe('copilot event handlers', () => {
    it('should register the copilot.message.created event handler', () => {
      expect(Object.keys(actionCable.events)).toContain(
        'copilot.message.created'
      );
      expect(actionCable.events['copilot.message.created']).toBe(
        actionCable.onCopilotMessageCreated
      );
    });

    it('should handle the copilot.message.created event through the ActionCable system', () => {
      const copilotData = {
        id: 2,
        content: 'This is a copilot message from ActionCable',
        conversation_id: 456,
        created_at: '2025-05-27T15:58:04-06:00',
        account_id: 1,
      };
      actionCable.onReceived({
        event: 'copilot.message.created',
        data: copilotData,
      });
      expect(mockDispatch).toHaveBeenCalledWith(
        'copilotMessages/upsert',
        copilotData
      );
    });
  });
});

describe('ActionCableConnector - Kanban Tests', () => {
  let store;
  let actionCable;
  let mockDispatch;
  let mockCommit;
  let mockHasModule;

  beforeEach(() => {
    vi.clearAllMocks();
    mockDispatch = vi.fn();
    mockCommit = vi.fn();
    mockHasModule = vi.fn(() => true);
    store = {
      $store: {
        dispatch: mockDispatch,
        commit: mockCommit,
        hasModule: mockHasModule,
        getters: {
          getCurrentAccountId: 1,
        },
      },
    };

    actionCable = ActionCableConnector.init(store.$store, 'test-token');
  });

  describe('kanban event handlers', () => {
    it('should register the kanban.task.created event handler', () => {
      expect(Object.keys(actionCable.events)).toContain('kanban.task.created');
      expect(actionCable.events['kanban.task.created']).toBe(
        actionCable.onKanbanTaskCreated
      );
    });

    it('should register the kanban.task.updated event handler', () => {
      expect(Object.keys(actionCable.events)).toContain('kanban.task.updated');
      expect(actionCable.events['kanban.task.updated']).toBe(
        actionCable.onKanbanTaskUpdated
      );
    });

    it('should register the kanban.task.deleted event handler', () => {
      expect(Object.keys(actionCable.events)).toContain('kanban.task.deleted');
      expect(actionCable.events['kanban.task.deleted']).toBe(
        actionCable.onKanbanTaskDeleted
      );
    });

    it('should register the kanban.step.created event handler', () => {
      expect(Object.keys(actionCable.events)).toContain('kanban.step.created');
      expect(actionCable.events['kanban.step.created']).toBe(
        actionCable.onKanbanStepCreated
      );
    });

    it('should register the kanban.step.updated event handler', () => {
      expect(Object.keys(actionCable.events)).toContain('kanban.step.updated');
      expect(actionCable.events['kanban.step.updated']).toBe(
        actionCable.onKanbanStepUpdated
      );
    });

    it('should register the kanban.board.updated event handler', () => {
      expect(Object.keys(actionCable.events)).toContain('kanban.board.updated');
      expect(actionCable.events['kanban.board.updated']).toBe(
        actionCable.onKanbanBoardUpdated
      );
    });

    it('should handle the kanban.task.created event', () => {
      const taskData = {
        id: 1,
        title: 'Test Task',
        board_id: 1,
        board_step_id: 1,
        account_id: 1,
        conversation_ids: [10, 20],
      };

      actionCable.onReceived({
        event: 'kanban.task.created',
        data: taskData,
      });

      expect(mockHasModule).toHaveBeenCalledWith('kanban');
      expect(mockDispatch).toHaveBeenCalledWith(
        'kanban/addTaskFromEvent',
        taskData
      );
      expect(mockCommit).toHaveBeenCalledWith(
        'UPDATE_CONVERSATION_KANBAN_TASK',
        { task: taskData, conversationId: 10 }
      );
      expect(mockCommit).toHaveBeenCalledWith(
        'UPDATE_CONVERSATION_KANBAN_TASK',
        { task: taskData, conversationId: 20 }
      );
    });

    it('should handle the kanban.task.updated event', () => {
      const taskData = {
        id: 1,
        title: 'Updated Task',
        board_id: 1,
        board_step_id: 2,
        account_id: 1,
      };

      actionCable.onReceived({
        event: 'kanban.task.updated',
        data: taskData,
      });

      expect(mockHasModule).toHaveBeenCalledWith('kanban');
      expect(mockDispatch).toHaveBeenCalledWith(
        'kanban/updateTaskFromEvent',
        taskData
      );
    });

    it('should handle the kanban.task.deleted event', () => {
      const taskData = {
        id: 1,
        board_id: 1,
        account_id: 1,
      };

      actionCable.onReceived({
        event: 'kanban.task.deleted',
        data: taskData,
      });

      expect(mockHasModule).toHaveBeenCalledWith('kanban');
      expect(mockDispatch).toHaveBeenCalledWith(
        'kanban/deleteTaskFromEvent',
        1
      );
    });

    it('should handle the kanban.step.created event', () => {
      const stepData = {
        id: 1,
        name: 'New Step',
        board_id: 1,
        account_id: 1,
      };

      actionCable.onReceived({
        event: 'kanban.step.created',
        data: stepData,
      });

      expect(mockHasModule).toHaveBeenCalledWith('kanban');
      expect(mockDispatch).toHaveBeenCalledWith(
        'kanban/addStepFromEvent',
        stepData
      );
    });

    it('should handle the kanban.step.updated event', () => {
      const stepData = {
        id: 1,
        name: 'Updated Step',
        board_id: 1,
        account_id: 1,
      };

      actionCable.onReceived({
        event: 'kanban.step.updated',
        data: stepData,
      });

      expect(mockHasModule).toHaveBeenCalledWith('kanban');
      expect(mockDispatch).toHaveBeenCalledWith(
        'kanban/updateStepFromEvent',
        stepData
      );
    });

    it('should handle the kanban.board.updated event', () => {
      const boardData = {
        id: 1,
        name: 'Updated Board',
        account_id: 1,
      };

      actionCable.onReceived({
        event: 'kanban.board.updated',
        data: boardData,
      });

      expect(mockHasModule).toHaveBeenCalledWith('kanban');
      expect(mockDispatch).toHaveBeenCalledWith(
        'kanban/updateBoardFromEvent',
        boardData
      );
    });

    it('should not dispatch kanban store events when module is not registered but still updates conversations', () => {
      mockHasModule.mockReturnValue(false);

      const taskData = {
        id: 1,
        title: 'Test Task',
        account_id: 1,
        conversation_ids: [10],
      };

      actionCable.onReceived({
        event: 'kanban.task.created',
        data: taskData,
      });

      expect(mockHasModule).toHaveBeenCalledWith('kanban');
      expect(mockDispatch).not.toHaveBeenCalled();
      expect(mockCommit).toHaveBeenCalledWith(
        'UPDATE_CONVERSATION_KANBAN_TASK',
        { task: taskData, conversationId: 10 }
      );
    });

    it('should not dispatch kanban events for different account', () => {
      const taskData = {
        id: 1,
        title: 'Test Task',
        account_id: 999, // Different account
      };

      actionCable.onReceived({
        event: 'kanban.task.created',
        data: taskData,
      });

      expect(mockDispatch).not.toHaveBeenCalled();
    });
  });
});
