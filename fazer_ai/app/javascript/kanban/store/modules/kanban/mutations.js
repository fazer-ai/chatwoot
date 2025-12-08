import * as types from '../../mutation-types';

export default {
  [types.SET_BOARDS](state, boards) {
    state.boards = boards;
  },
  [types.SET_SELECTED_BOARD_ID](state, id) {
    state.selectedBoardId = id;
  },
  [types.SET_STEPS](state, steps) {
    state.steps = steps;
  },
  [types.SET_TASKS](state, tasks) {
    state.tasks = tasks;
  },
  [types.SET_KANBAN_LOADING](state, isLoading) {
    state.isLoading = isLoading;
  },
  [types.ADD_TASK](state, task) {
    if (!state.tasks.some(t => t.id === task.id)) {
      state.tasks.push(task);
    }
  },
  [types.UPDATE_TASK](state, updatedTask) {
    const index = state.tasks.findIndex(t => t.id === updatedTask.id);
    if (index !== -1) {
      state.tasks.splice(index, 1, updatedTask);
    }
  },
  [types.DELETE_TASK](state, taskId) {
    state.tasks = state.tasks.filter(t => t.id !== taskId);
  },
  [types.UPDATE_STEP](state, updatedStep) {
    const index = state.steps.findIndex(s => s.id === updatedStep.id);
    if (index !== -1) {
      state.steps.splice(index, 1, updatedStep);
    }
  },
  [types.ADD_STEP](state, step) {
    if (!state.steps.some(s => s.id === step.id)) {
      state.steps.push(step);
    }
  },
  [types.ADD_BOARD](state, board) {
    state.boards.push(board);
  },
  [types.UPDATE_BOARD](state, updatedBoard) {
    const index = state.boards.findIndex(f => f.id === updatedBoard.id);
    if (index !== -1) {
      state.boards.splice(index, 1, updatedBoard);
    }
  },
  [types.DELETE_BOARD](state, boardId) {
    const index = state.boards.findIndex(f => f.id === boardId);
    if (index !== -1) {
      state.boards.splice(index, 1);
    }
  },
  [types.SET_KANBAN_PREFERENCES](state, preferences) {
    state.preferences = { ...state.preferences, ...preferences };
  },
};
