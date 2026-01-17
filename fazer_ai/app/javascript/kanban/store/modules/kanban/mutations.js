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
  [types.SET_KANBAN_LOADING](state, isLoading) {
    state.isLoading = isLoading;
  },
  [types.ADD_TASK](state, task) {
    const stepId = task.board_step_id;
    if (!state.stepTasks[stepId]) {
      state.stepTasks[stepId] = [];
    }
    if (!state.stepTasks[stepId].some(t => t.id === task.id)) {
      state.stepTasks[stepId] = [task, ...state.stepTasks[stepId]];

      // Update step task count
      const step = state.steps.find(s => String(s.id) === String(stepId));
      if (step) {
        step.tasks_count += 1;
        // Note: We don't update filtered_tasks_count here because we don't know
        // if the new task matches the current filter criteria
      }
    }
  },
  [types.UPDATE_TASK](state, updatedTask) {
    // Find old task in stepTasks
    let oldTask = null;
    let oldStepId = null;
    const stepIds = Object.keys(state.stepTasks);
    stepIds.some(stepId => {
      const found = state.stepTasks[stepId]?.find(t => t.id === updatedTask.id);
      if (found) {
        oldTask = found;
        oldStepId = stepId;
        return true;
      }
      return false;
    });

    if (!oldTask) return;

    const newStepId = updatedTask.board_step_id;

    if (oldStepId !== String(newStepId) && oldStepId !== newStepId) {
      // Moving to different step
      // Remove from old step
      state.stepTasks[oldStepId] = state.stepTasks[oldStepId].filter(
        t => t.id !== updatedTask.id
      );
      // Add to new step (at the end - we don't have position info from websocket)
      if (!state.stepTasks[newStepId]) {
        state.stepTasks[newStepId] = [];
      }
      // Filter out any duplicate first, then append
      state.stepTasks[newStepId] = [
        ...state.stepTasks[newStepId].filter(t => t.id !== updatedTask.id),
        updatedTask,
      ];

      // Update step task counts
      const oldStep = state.steps.find(s => String(s.id) === String(oldStepId));
      if (oldStep && oldStep.tasks_count > 0) {
        oldStep.tasks_count -= 1;
        // Note: We don't update filtered_tasks_count here because we don't know
        // if the task matched the current filter criteria
      }
      const newStep = state.steps.find(s => String(s.id) === String(newStepId));
      if (newStep) {
        newStep.tasks_count += 1;
        // Note: We don't update filtered_tasks_count here because we don't know
        // if the task matches the current filter criteria
      }
    } else {
      // Update in same step
      const stepIndex = state.stepTasks[oldStepId].findIndex(
        t => t.id === updatedTask.id
      );
      if (stepIndex !== -1) {
        state.stepTasks[oldStepId].splice(stepIndex, 1, updatedTask);
      }
    }
  },
  [types.MOVE_TASK](
    state,
    { task, sourceStepId, destinationStepId, insertBeforeTaskId }
  ) {
    // Remove from source step
    if (state.stepTasks[sourceStepId]) {
      state.stepTasks[sourceStepId] = state.stepTasks[sourceStepId].filter(
        t => t.id !== task.id
      );
    }

    // Initialize destination step if needed
    if (!state.stepTasks[destinationStepId]) {
      state.stepTasks[destinationStepId] = [];
    }

    // Insert into destination step
    if (insertBeforeTaskId) {
      const index = state.stepTasks[destinationStepId].findIndex(
        t => t.id === insertBeforeTaskId
      );
      if (index !== -1) {
        state.stepTasks[destinationStepId].splice(index, 0, task);
      } else {
        state.stepTasks[destinationStepId].push(task);
      }
    } else {
      state.stepTasks[destinationStepId].push(task);
    }

    // Update counts if moving between steps
    if (sourceStepId !== destinationStepId) {
      const oldStep = state.steps.find(
        s => String(s.id) === String(sourceStepId)
      );
      if (oldStep && oldStep.tasks_count > 0) {
        oldStep.tasks_count -= 1;
        // Note: We don't update filtered_tasks_count here because we don't know
        // if the task matched the current filter criteria
      }
      const newStep = state.steps.find(
        s => String(s.id) === String(destinationStepId)
      );
      if (newStep) {
        newStep.tasks_count += 1;
        // Note: We don't update filtered_tasks_count here because we don't know
        // if the task matches the current filter criteria
      }
    }
  },
  [types.DELETE_TASK](state, taskId) {
    // Find and remove task from stepTasks
    const stepIds = Object.keys(state.stepTasks);
    stepIds.some(stepId => {
      const task = state.stepTasks[stepId]?.find(t => t.id === taskId);
      if (task) {
        state.stepTasks[stepId] = state.stepTasks[stepId].filter(
          t => t.id !== taskId
        );

        // Update step task count
        const step = state.steps.find(s => String(s.id) === String(stepId));
        if (step && step.tasks_count > 0) {
          step.tasks_count -= 1;
          // Note: We don't update filtered_tasks_count here because we don't know
          // if the deleted task was part of the filtered set
        }
        return true;
      }
      return false;
    });
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

  // Step-based task loading mutations
  [types.SET_STEP_TASKS](state, { stepId, tasks }) {
    state.stepTasks = { ...state.stepTasks, [stepId]: tasks };
    state.stepFetched = { ...state.stepFetched, [stepId]: true };
  },
  [types.APPEND_STEP_TASKS](state, { stepId, tasks }) {
    const existing = state.stepTasks[stepId] || [];
    const newTaskIds = new Set(tasks.map(t => t.id));
    const filtered = existing.filter(t => !newTaskIds.has(t.id));
    state.stepTasks = { ...state.stepTasks, [stepId]: [...filtered, ...tasks] };
  },
  [types.SET_STEP_LOADING](state, { stepId, isLoading }) {
    state.stepLoading = { ...state.stepLoading, [stepId]: isLoading };
  },
  [types.SET_STEP_META](state, { stepId, meta }) {
    state.stepMeta = { ...state.stepMeta, [stepId]: meta };
  },
  [types.RESET_STEP_TASKS](state) {
    state.stepTasks = {};
    state.stepMeta = {};
    state.stepLoading = {};
    state.stepFetched = {};
    state.stepRequestVersion = {};
  },
  [types.INCREMENT_STEP_REQUEST_VERSION](state, stepId) {
    const current = state.stepRequestVersion[stepId] || 0;
    state.stepRequestVersion = {
      ...state.stepRequestVersion,
      [stepId]: current + 1,
    };
  },
};
