import actions from './actions';
import getters from './getters';
import mutations from './mutations';

const state = {
  boards: [],
  selectedBoardId: null,
  steps: [],
  isLoading: false,
  preferences: {},
  stepTasks: {}, // { stepId: [tasks] }
  stepMeta: {}, // { stepId: { totalCount, page, perPage, hasMore } }
  stepLoading: {}, // { stepId: boolean }
  stepFetched: {}, // { stepId: boolean } - tracks if step has been initially fetched
  stepRequestVersion: {}, // { stepId: number } - tracks request version to discard stale responses
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
