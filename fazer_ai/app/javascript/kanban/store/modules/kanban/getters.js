export default {
  getBoards: state => state.boards,

  activeBoard: state => state.boards.find(f => f.id === state.selectedBoardId),

  // Returns tasks as-is from BE - sorting is handled server-side
  stepTasksMap: state => {
    const result = {};
    state.steps.forEach(step => {
      result[step.id] = state.stepTasks[step.id] || [];
    });
    return result;
  },

  stepMetaMap: state => state.stepMeta,
  stepLoadingMap: state => state.stepLoading,
  stepFetchedMap: state => state.stepFetched,

  isStepLoading: state => stepId => state.stepLoading[stepId] || false,
  isStepFetched: state => stepId => state.stepFetched[stepId] || false,
  stepHasMore: state => stepId => state.stepMeta[stepId]?.hasMore || false,

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
    const sorted = [...state.steps].sort((a, b) => {
      const indexA = orderMap.has(a.id) ? orderMap.get(a.id) : Infinity;
      const indexB = orderMap.has(b.id) ? orderMap.get(b.id) : Infinity;
      return indexA - indexB;
    });

    const lastStepId =
      activeBoard.steps_order[activeBoard.steps_order.length - 1];
    return sorted.map(step => {
      let inferredStatus = 'open';
      if (sorted.length <= 1) {
        inferredStatus = 'open';
      } else if (step.cancelled) {
        inferredStatus = 'cancelled';
      } else if (step.id === lastStepId) {
        inferredStatus = 'completed';
      }
      return { ...step, inferred_task_status: inferredStatus };
    });
  },
};
