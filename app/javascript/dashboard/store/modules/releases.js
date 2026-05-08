import ReleasesAPI from '../../api/releases';
import types from '../mutation-types';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const state = {
  records: [],
  uiFlags: {
    fetchingList: false,
    isDismissing: false,
  },
};

const getters = {
  getReleases(_state) {
    return _state.records;
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

const actions = {
  async fetch({ commit }) {
    commit('SET_UI_FLAG', { fetchingList: true });
    try {
      const { data } = await ReleasesAPI.get();
      commit('SET_RELEASES', data?.data || []);
      return data?.data || [];
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { fetchingList: false });
    }
  },

  async dismiss({ commit }, tag) {
    commit('SET_UI_FLAG', { isDismissing: true });
    try {
      await ReleasesAPI.dismissRelease(tag);
      commit(types.SET_CURRENT_USER_LAST_SEEN_RELEASE, tag, { root: true });
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isDismissing: false });
    }
  },
};

const mutations = {
  SET_UI_FLAG(_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  SET_RELEASES(_state, data) {
    _state.records = data;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
