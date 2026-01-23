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
      if (preferences) {
        commit(types.SET_KANBAN_PREFERENCES, preferences);
      }
      commit(types.SET_BOARDS, boards);
    } catch {
      // Ignore error
    } finally {
      commit(types.SET_KANBAN_LOADING, false);
    }
  },

  async fetchSteps({ commit, state }, { boardId, agentId, inboxId } = {}) {
    const targetBoardId = boardId || state.selectedBoardId;
    if (!targetBoardId) return;
    try {
      const response = await BoardsAPI.getSteps(targetBoardId, {
        agentId,
        inboxId,
      });
      if (state.selectedBoardId === targetBoardId) {
        commit(types.SET_STEPS, response.data.steps);
      }
    } catch {
      // Ignore error
    }
  },

  async setActiveBoard({ commit, dispatch }, { boardId, agentId, inboxId }) {
    commit(types.SET_KANBAN_LOADING, true);
    commit(types.SET_SELECTED_BOARD_ID, boardId);
    // Clear steps immediately to prevent stale data triggering task fetches
    commit(types.SET_STEPS, []);
    try {
      // Only fetch steps - tasks will be fetched per step by the component
      await dispatch('fetchSteps', { boardId, agentId, inboxId });
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
    // Find task in stepTasks
    let originalTask = null;
    const stepIds = Object.keys(state.stepTasks);
    stepIds.some(stepId => {
      originalTask = state.stepTasks[stepId]?.find(t => t.id === id);
      return !!originalTask;
    });

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
    { commit, state, dispatch },
    { taskId, destinationStepId, insertBeforeTaskId, refreshStepId = null }
  ) {
    // Find task in stepTasks
    let task = null;
    const stepIds = Object.keys(state.stepTasks);
    stepIds.some(stepId => {
      task = state.stepTasks[stepId]?.find(t => t.id === taskId);
      return !!task;
    });
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

    commit(types.MOVE_TASK, {
      task: { ...task, board_step_id: destinationStepId },
      sourceStepId,
      destinationStepId,
      insertBeforeTaskId,
    });

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

      // Refresh step tasks after successful move (e.g., when sorting by last activity)
      if (refreshStepId) {
        dispatch('fetchTasksForStep', {
          stepId: refreshStepId,
          page: 1,
          perPage: 10,
        });
      }
    } catch {
      // Revert based on original task state
      // We don't have the original insertBeforeTaskId easily available to restore exact position
      // but UPDATE_TASK will at least put it back in the correct step list
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

  async deleteStep({ dispatch, commit }, { boardId, stepId }) {
    await BoardsAPI.deleteStep(boardId, stepId);
    // Reset step tasks and re-fetch steps
    commit(types.RESET_STEP_TASKS);
    await dispatch('fetchSteps', { boardId });
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

  updateTaskFromEvent({ commit, state }, task) {
    // Check if task moved to a different step
    let currentStepId = null;
    const stepIds = Object.keys(state.stepTasks);
    stepIds.some(stepId => {
      const found = state.stepTasks[stepId]?.find(t => t.id === task.id);
      if (found) {
        currentStepId = stepId;
        return true;
      }
      return false;
    });

    const newStepId = task.board_step_id;
    const stepChanged =
      currentStepId &&
      String(currentStepId) !== String(newStepId) &&
      currentStepId !== newStepId;

    // Check if this is a move operation (has explicit position info)
    // insert_before_task_id key is only present during move operations
    const hasMovePositionInfo = Object.hasOwn(task, 'insert_before_task_id');

    // If we have position info, use MOVE_TASK (works for both between-step and within-step moves)
    if (hasMovePositionInfo && currentStepId) {
      commit(types.MOVE_TASK, {
        task: { ...task, board_step_id: newStepId },
        sourceStepId: currentStepId,
        destinationStepId: newStepId,
        insertBeforeTaskId: task.insert_before_task_id,
      });
    } else if (stepChanged) {
      // Step changed but no position info - use MOVE_TASK, will append to end
      commit(types.MOVE_TASK, {
        task: { ...task, board_step_id: newStepId },
        sourceStepId: currentStepId,
        destinationStepId: newStepId,
        insertBeforeTaskId: null,
      });
    } else {
      // Same step, no position info - just update properties in place
      commit(types.UPDATE_TASK, task);
    }
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

  // Step-based task loading actions
  async fetchTasksForStep(
    { commit, state },
    { stepId, page = 1, perPage = 10, append = false }
  ) {
    // Block all concurrent requests while loading (prevents rapid scroll from queueing multiple requests)
    if (state.stepLoading[stepId]) return;

    // Increment request version to invalidate any pending requests
    commit(types.INCREMENT_STEP_REQUEST_VERSION, stepId);
    const requestVersion = state.stepRequestVersion[stepId];

    commit(types.SET_STEP_LOADING, { stepId, isLoading: true });

    try {
      const activeBoardId = state.selectedBoardId;
      const savedSort = state.preferences.task_sorting?.[activeBoardId] || {};
      const sort = savedSort.sort || 'position';
      const order = savedSort.order || 'asc';

      const boardFilters =
        state.preferences.board_filters?.[activeBoardId] || {};
      const agentId = boardFilters.agent_id;
      const inboxId = boardFilters.inbox_id;

      const response = await TasksAPI.getByStep(stepId, {
        page,
        perPage,
        sort: sort === 'position' ? undefined : sort,
        order: sort === 'position' ? undefined : order,
        agentId: agentId !== 'all' ? agentId : undefined,
        inboxId: inboxId !== 'all' ? inboxId : undefined,
      });

      // Discard response if a newer request was made
      if (state.stepRequestVersion[stepId] !== requestVersion) {
        return;
      }

      const { tasks, meta } = response.data;

      if (append) {
        commit(types.APPEND_STEP_TASKS, { stepId, tasks });
      } else {
        commit(types.SET_STEP_TASKS, { stepId, tasks });
      }

      if (meta) {
        // Transform snake_case keys to camelCase
        // Safety: if API returns empty tasks but claims hasMore, force hasMore to false
        // This prevents infinite scroll loops when filters cause count mismatches
        const actualHasMore = meta.has_more && tasks.length > 0;
        const transformedMeta = {
          totalCount: meta.total_count,
          page: meta.page,
          perPage: meta.per_page,
          hasMore: actualHasMore,
        };
        commit(types.SET_STEP_META, { stepId, meta: transformedMeta });
      }
    } catch {
      // On error, set hasMore to false to prevent stuck infinite scroll
      commit(types.SET_STEP_META, {
        stepId,
        meta: { ...state.stepMeta[stepId], hasMore: false },
      });
    } finally {
      // Always clear loading state to prevent stuck states
      commit(types.SET_STEP_LOADING, { stepId, isLoading: false });
    }
  },

  async fetchMoreTasksForStep({ dispatch, state }, stepId) {
    const meta = state.stepMeta[stepId];
    if (!meta || !meta.hasMore) return;

    const nextPage = meta.page + 1;
    await dispatch('fetchTasksForStep', {
      stepId,
      page: nextPage,
      perPage: meta.perPage,
      append: true,
    });
  },

  async initializeStepTasks({ commit, dispatch }, { stepIds }) {
    commit(types.RESET_STEP_TASKS);

    // Fetch first page for each step in parallel
    await Promise.all(
      stepIds.map(stepId =>
        dispatch('fetchTasksForStep', { stepId, page: 1, perPage: 10 })
      )
    );
  },

  resetStepTasks({ commit }) {
    commit(types.RESET_STEP_TASKS);
  },

  async updateTaskSorting({ commit, state }, { boardId, sort, order }) {
    const previousPreferences = { ...state.preferences };
    const newPreferences = {
      ...state.preferences,
      task_sorting: {
        ...(state.preferences.task_sorting || {}),
        [boardId]: { sort, order },
      },
    };
    commit(types.SET_KANBAN_PREFERENCES, newPreferences);

    try {
      await PreferencesAPI.update({
        task_sorting: newPreferences.task_sorting,
      });
    } catch {
      commit(types.SET_KANBAN_PREFERENCES, previousPreferences);
    }
  },
};
