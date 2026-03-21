import InternalChatMessagesAPI from '../../../api/internalChatMessages';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const state = {
  uiFlags: {
    isCreating: false,
    isVoting: false,
  },
};

const getters = {
  getUIFlags: _state => _state.uiFlags,
};

const actions = {
  createPoll: async ({ commit, dispatch }, { channelId, data }) => {
    commit('SET_UI_FLAG', { isCreating: true });
    try {
      const response = await InternalChatMessagesAPI.createPoll(
        channelId,
        data
      );
      dispatch(
        'internalChat/messages/addMessageFromCable',
        { channelId, message: response.data },
        { root: true }
      );
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    } finally {
      commit('SET_UI_FLAG', { isCreating: false });
    }
  },

  vote: async ({ commit, dispatch }, { channelId, messageId, optionId }) => {
    commit('SET_UI_FLAG', { isVoting: true });
    try {
      const response = await InternalChatMessagesAPI.votePoll(
        channelId,
        messageId,
        optionId
      );
      dispatch(
        'internalChat/messages/updateMessageFromCable',
        { channelId, message: response.data },
        { root: true }
      );
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    } finally {
      commit('SET_UI_FLAG', { isVoting: false });
    }
  },

  unvote: async ({ commit, dispatch }, { channelId, messageId, optionId }) => {
    commit('SET_UI_FLAG', { isVoting: true });
    try {
      const response = await InternalChatMessagesAPI.unvotePoll(
        channelId,
        messageId,
        optionId
      );
      dispatch(
        'internalChat/messages/updateMessageFromCable',
        { channelId, message: response.data },
        { root: true }
      );
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    } finally {
      commit('SET_UI_FLAG', { isVoting: false });
    }
  },
};

const mutations = {
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
