import InternalChatDraftsAPI from '../../../api/internalChatDrafts';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const state = {
  records: {},
  uiFlags: {
    isFetching: false,
  },
};

const getters = {
  getDrafts: _state => {
    return Object.values(_state.records);
  },

  getDraftByChannelId: _state => channelId => {
    return (
      Object.values(_state.records).find(
        draft => draft.channel_id === channelId
      ) || null
    );
  },

  getUIFlags: _state => _state.uiFlags,
};

const actions = {
  fetchDrafts: async ({ commit }) => {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const response = await InternalChatDraftsAPI.getDrafts();
      const drafts = response.data;
      commit('SET_DRAFTS', drafts);
      return drafts;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  saveDraft: async ({ commit }, { channelId, content }) => {
    try {
      const response = await InternalChatDraftsAPI.saveDraft({
        channel_id: channelId,
        content,
      });
      commit('SET_DRAFT', response.data);
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    }
  },

  deleteDraft: async ({ commit }, draftId) => {
    try {
      await InternalChatDraftsAPI.deleteDraft(draftId);
      commit('DELETE_DRAFT', draftId);
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    }
  },
};

const mutations = {
  SET_DRAFTS(_state, drafts) {
    const records = {};
    drafts.forEach(draft => {
      records[draft.id] = draft;
    });
    _state.records = records;
  },

  SET_DRAFT(_state, draft) {
    _state.records = {
      ..._state.records,
      [draft.id]: draft,
    };
  },

  DELETE_DRAFT(_state, draftId) {
    const { [draftId]: _, ...rest } = _state.records;
    _state.records = rest;
  },

  SET_UI_FLAG(_state, flags) {
    _state.uiFlags = { ..._state.uiFlags, ...flags };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
