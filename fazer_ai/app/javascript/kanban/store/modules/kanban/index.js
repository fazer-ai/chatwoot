import actions from './actions';
import getters from './getters';
import mutations from './mutations';

const state = {
  boards: [],
  selectedBoardId: null,
  steps: [],
  tasks: [],
  isLoading: false,
  preferences: {},
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
