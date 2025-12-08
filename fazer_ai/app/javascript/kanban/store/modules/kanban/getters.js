export default {
  getBoards: state => state.boards,

  activeBoard: state => state.boards.find(f => f.id === state.selectedBoardId),

  tasksByStep: state => {
    const grouped = {};
    state.steps.forEach(step => {
      grouped[step.id] = [];
    });

    state.tasks.forEach(task => {
      if (grouped[task.board_step_id]) {
        grouped[task.board_step_id].push(task);
      }
    });

    const activeBoardId = state.selectedBoardId;
    const currentSort = state.preferences.task_sorting?.[activeBoardId]?.sort;
    const isManualSort = !currentSort || currentSort === 'position';

    state.steps.forEach(step => {
      const tasksOrder = state.preferences.tasks_order?.[step.id];
      if (isManualSort && tasksOrder && tasksOrder.length > 0) {
        const orderMap = new Map(tasksOrder.map((id, index) => [id, index]));
        grouped[step.id].sort((a, b) => {
          const indexA = orderMap.has(a.id) ? orderMap.get(a.id) : Infinity;
          const indexB = orderMap.has(b.id) ? orderMap.get(b.id) : Infinity;
          return indexA - indexB;
        });
      }
    });

    return grouped;
  },

  orderedSteps: state => {
    const activeBoard = state.boards.find(f => f.id === state.selectedBoardId);
    if (
      !activeBoard ||
      !activeBoard.steps_order ||
      activeBoard.steps_order.length === 0
    ) {
      return state.steps;
    }

    const orderMap = new Map(
      activeBoard.steps_order.map((id, index) => [id, index])
    );
    return [...state.steps].sort((a, b) => {
      const indexA = orderMap.has(a.id) ? orderMap.get(a.id) : Infinity;
      const indexB = orderMap.has(b.id) ? orderMap.get(b.id) : Infinity;
      return indexA - indexB;
    });
  },
};
