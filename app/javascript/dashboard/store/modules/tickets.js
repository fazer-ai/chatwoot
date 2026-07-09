import { throwErrorMessage } from 'dashboard/store/utils/api';
import * as types from '../mutation-types';
import TicketsAPI from '../../api/tickets';

const state = {
  uiFlags: {
    creatingItem: false,
    addingComment: false,
  },
};

const getters = {
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

const actions = {
  create: async ({ commit }, payload) => {
    commit(types.default.SET_TICKETS_UI_FLAG, { creatingItem: true });
    try {
      const response = await TicketsAPI.create(payload);
      commit(types.default.SET_TICKETS_UI_FLAG, { creatingItem: false });
      return response.data;
    } catch (error) {
      commit(types.default.SET_TICKETS_UI_FLAG, { creatingItem: false });
      return throwErrorMessage(error);
    }
  },
  addComment: async ({ commit }, { id, comment }) => {
    commit(types.default.SET_TICKETS_UI_FLAG, { addingComment: true });
    try {
      await TicketsAPI.addComment(id, { comment });
      commit(types.default.SET_TICKETS_UI_FLAG, { addingComment: false });
    } catch (error) {
      commit(types.default.SET_TICKETS_UI_FLAG, { addingComment: false });
      return throwErrorMessage(error);
    }
    return true;
  },
};

const mutations = {
  [types.default.SET_TICKETS_UI_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
