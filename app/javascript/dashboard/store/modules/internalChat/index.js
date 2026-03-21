import { getters } from './getters';
import { actions } from './actions';
import { mutations } from './mutations';
import messages from './messages';
import typingStatus from './typingStatus';
import polls from './polls';
import drafts from './drafts';

const state = {
  records: {},
  categories: [],
  activeChannelId: null,
  uiFlags: {
    isFetching: false,
    isCreating: false,
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
  modules: {
    messages,
    typingStatus,
    polls,
    drafts,
  },
};
