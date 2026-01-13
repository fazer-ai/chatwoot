import * as types from '../../mutation-types';
import BoardsAPI from 'kanban/api/boards';
import PreferencesAPI from 'kanban/api/preferences';
import TasksAPI from 'kanban/api/tasks';

export default {
  async fetchBoards({ commit }, params = {}) {
    commit(types.SET_KANBAN_LOADING, true);
    try {
      const response = await BoardsAPI.get(params);
      const { boards, preferences } = response.data;
      commit(types.SET_BOARDS, boards);
      if (preferences) {
        commit(types.SET_KANBAN_PREFERENCES, preferences);
      }
    } catch {
      // Ignore error
    } finally {
      commit(types.SET_KANBAN_LOADING, false);
    }
  },

  async fetchSteps({ commit, state }, boardId) {
    if (!boardId) return;
    try {
      const response = await BoardsAPI.getSteps(boardId);
      if (state.selectedBoardId === boardId) {
        commit(types.SET_STEPS, response.data.steps);
      }
    } catch {
      // Ignore error
    }
  },

  async fetchTasks({ commit, state }, { boardId, sort, order }) {
    if (!boardId) return;

    if (sort) {
      const newPreferences = {
        ...state.preferences,
        task_sorting: {
          ...(state.preferences.task_sorting || {}),
          [boardId]: { sort, order },
        },
      };
      commit(types.SET_KANBAN_PREFERENCES, newPreferences);
    }

    try {
      const response = await TasksAPI.get({
        board_id: boardId,
        sort,
        order,
      });
      if (state.selectedBoardId === boardId) {
        commit(types.SET_TASKS, response.data.tasks);
        if (response.data.preferences) {
          commit(types.SET_KANBAN_PREFERENCES, response.data.preferences);
        }
      }
    } catch {
      // Ignore error
    }
  },

  async setActiveBoard({ commit, dispatch }, { boardId, sort, order }) {
    commit(types.SET_KANBAN_LOADING, true);
    commit(types.SET_SELECTED_BOARD_ID, boardId);
    try {
      await Promise.all([
        dispatch('fetchSteps', boardId),
        dispatch('fetchTasks', { boardId, sort, order }),
      ]);
    } finally {
      commit(types.SET_KANBAN_LOADING, false);
    }
  },

  async toggleFavoriteBoard({ commit, state }, boardId) {
    const previousFavorites = [...(state.preferences.favorite_board_ids || [])];
    let newFavorites;

    if (previousFavorites.includes(boardId)) {
      newFavorites = previousFavorites.filter(id => id !== boardId);
    } else {
      newFavorites = [...previousFavorites, boardId];
    }

    commit(types.SET_KANBAN_PREFERENCES, {
      ...state.preferences,
      favorite_board_ids: newFavorites,
    });

    try {
      const response = await BoardsAPI.toggleFavorite(boardId);
      const { favorite_board_ids } = response.data;

      commit(types.SET_KANBAN_PREFERENCES, {
        ...state.preferences,
        favorite_board_ids,
      });
    } catch {
      commit(types.SET_KANBAN_PREFERENCES, {
        ...state.preferences,
        favorite_board_ids: previousFavorites,
      });
    }
  },

  async createBoard({ commit }, boardData) {
    const response = await BoardsAPI.create(boardData);
    commit(types.ADD_BOARD, response.data);
    return response.data;
  },

  async createTask({ commit }, taskData) {
    const response = await TasksAPI.create(taskData);
    commit(types.ADD_TASK, response.data);
    return response.data;
  },

  async updateTask({ commit, state }, { id, task }) {
    const originalTask = state.tasks.find(t => t.id === id);

    if (originalTask) {
      const updates = task ? { ...task } : {};
      const optimisticTask = { ...originalTask, ...updates };
      commit(types.UPDATE_TASK, optimisticTask);
    }

    try {
      const payload = { task };
      const response = await TasksAPI.update(id, payload);
      commit(types.UPDATE_TASK, response.data);
      return response.data;
    } catch (error) {
      if (originalTask) {
        commit(types.UPDATE_TASK, originalTask);
      }
      throw error;
    }
  },

  async moveTask(
    { commit, state },
    { taskId, destinationStepId, insertBeforeTaskId }
  ) {
    const task = state.tasks.find(t => t.id === taskId);
    if (!task) return;

    const sourceStepId = task.board_step_id;
    const sourceStep = state.steps.find(s => s.id === sourceStepId);
    const destinationStep = state.steps.find(s => s.id === destinationStepId);

    if (!sourceStep || !destinationStep) return;

    const getTasksOrder = stepId =>
      state.preferences.tasks_order?.[stepId] || [];

    let sourceStepTasksOrder = [...getTasksOrder(sourceStepId)];
    sourceStepTasksOrder = sourceStepTasksOrder.filter(id => id !== taskId);

    let destinationStepTasksOrder;
    if (sourceStepId === destinationStepId) {
      destinationStepTasksOrder = [...sourceStepTasksOrder];
    } else {
      destinationStepTasksOrder = [...getTasksOrder(destinationStepId)];
    }

    if (insertBeforeTaskId) {
      const index = destinationStepTasksOrder.indexOf(insertBeforeTaskId);
      if (index !== -1) {
        destinationStepTasksOrder.splice(index, 0, taskId);
      } else {
        destinationStepTasksOrder.push(taskId);
      }
    } else {
      destinationStepTasksOrder.push(taskId);
    }

    commit(types.UPDATE_TASK, { ...task, board_step_id: destinationStepId });

    const newPreferences = {
      ...state.preferences,
      tasks_order: {
        ...(state.preferences.tasks_order || {}),
        [sourceStepId]: sourceStepTasksOrder,
        [destinationStepId]: destinationStepTasksOrder,
      },
    };

    const originalPreferences = { ...state.preferences };
    commit(types.SET_KANBAN_PREFERENCES, newPreferences);

    try {
      await TasksAPI.move(taskId, {
        board_step_id: destinationStepId,
        insert_before_task_id: insertBeforeTaskId,
      });
    } catch {
      commit(types.UPDATE_TASK, task);
      commit(types.SET_KANBAN_PREFERENCES, originalPreferences);
    }
  },

  async deleteTask({ commit }, id) {
    await TasksAPI.delete(id);
    commit(types.DELETE_TASK, id);
  },

  async updateStep({ commit, state }, { boardId, stepId, ...data }) {
    const originalStep = state.steps.find(s => s.id === stepId);
    if (originalStep && data.step) {
      const optimisticStep = { ...originalStep, ...data.step };
      commit(types.UPDATE_STEP, optimisticStep);
    }

    try {
      const response = await BoardsAPI.updateStep(boardId, stepId, data);
      commit(types.UPDATE_STEP, response.data);
      return response.data;
    } catch (error) {
      if (originalStep) {
        commit(types.UPDATE_STEP, originalStep);
      }
      throw error;
    }
  },

  async deleteStep({ dispatch }, { boardId, stepId }) {
    await BoardsAPI.deleteStep(boardId, stepId);
    await Promise.all([
      dispatch('fetchTasks', { boardId }),
      dispatch('fetchSteps', boardId),
    ]);
  },

  async createStep({ commit }, { boardId, ...stepData }) {
    const response = await BoardsAPI.createStep(boardId, stepData);
    commit(types.ADD_STEP, response.data);
    return response.data;
  },

  async updateBoard({ commit }, { id, board }) {
    const response = await BoardsAPI.update(id, { board });
    commit(types.UPDATE_BOARD, response.data);
    return response.data;
  },

  async updateBoardAgents({ commit }, { boardId, agentIds }) {
    const response = await BoardsAPI.updateAgents(boardId, agentIds);
    commit(types.UPDATE_BOARD, response.data);
    return response.data;
  },

  async updateBoardInboxes({ commit }, { boardId, inboxIds }) {
    const response = await BoardsAPI.updateInboxes(boardId, inboxIds);
    commit(types.UPDATE_BOARD, response.data);
    return response.data;
  },

  async deleteBoard({ commit }, boardId) {
    await BoardsAPI.delete(boardId);
    commit(types.DELETE_BOARD, boardId);
  },

  async updateBoardFilters(
    { commit, state },
    { boardId, agentId, inboxId, showCompleted, showCancelled }
  ) {
    const previousPreferences = { ...state.preferences };
    const preferencesToUpdate = {
      board_filters: {
        [boardId]: {
          agent_id: agentId,
          inbox_id: inboxId,
          show_completed: showCompleted,
          show_cancelled: showCancelled,
        },
      },
    };

    commit(types.SET_KANBAN_PREFERENCES, {
      ...state.preferences,
      board_filters: {
        ...(state.preferences.board_filters || {}),
        [boardId]: {
          agent_id: agentId,
          inbox_id: inboxId,
          show_completed: showCompleted,
          show_cancelled: showCancelled,
        },
      },
    });

    try {
      await PreferencesAPI.update(preferencesToUpdate);
    } catch {
      commit(types.SET_KANBAN_PREFERENCES, previousPreferences);
    }
  },

  addTaskFromEvent({ commit }, task) {
    commit(types.ADD_TASK, task);
  },

  updateTaskFromEvent({ commit }, task) {
    commit(types.UPDATE_TASK, task);
  },

  deleteTaskFromEvent({ commit }, taskId) {
    commit(types.DELETE_TASK, taskId);
  },

  addStepFromEvent({ commit }, step) {
    commit(types.ADD_STEP, step);
  },

  updateStepFromEvent({ commit }, step) {
    commit(types.UPDATE_STEP, step);
  },

  updateBoardFromEvent({ commit }, board) {
    commit(types.UPDATE_BOARD, board);
  },
};
