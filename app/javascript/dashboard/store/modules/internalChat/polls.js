import InternalChatPollsAPI from '../../../api/internalChatPolls';
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
      const response = await InternalChatPollsAPI.createPoll({
        channel_id: channelId,
        ...data,
      });
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

  vote: async ({ commit, dispatch }, { pollId, optionId, channelId }) => {
    commit('SET_UI_FLAG', { isVoting: true });
    try {
      const response = await InternalChatPollsAPI.vote(pollId, optionId);
      if (channelId && response.data) {
        dispatch(
          'internalChat/messages/updateMessageFromCable',
          { channelId, message: response.data },
          { root: true }
        );
      }
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    } finally {
      commit('SET_UI_FLAG', { isVoting: false });
    }
  },

  unvote: async ({ commit, dispatch }, { pollId, optionId, channelId }) => {
    commit('SET_UI_FLAG', { isVoting: true });
    try {
      const response = await InternalChatPollsAPI.unvote(pollId, optionId);
      if (channelId && response.data) {
        dispatch(
          'internalChat/messages/updateMessageFromCable',
          { channelId, message: response.data },
          { root: true }
        );
      }
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    } finally {
      commit('SET_UI_FLAG', { isVoting: false });
    }
  },

  updatePollFromCable: ({ dispatch, rootGetters }, { channelId, poll }) => {
    const messageId = poll.internal_chat_message_id;
    if (!messageId) return;

    const existingMessage = rootGetters['internalChat/messages/getMessageById'](
      channelId,
      messageId
    );
    const existingAttrs = existingMessage?.content_attributes || {};
    const existingPoll = existingAttrs.poll || {};
    const existingOptions = existingPoll.options || [];

    // Preserve per-user voted flags from local state (cable data is not user-specific)
    const mergedOptions = (poll.options || []).map(opt => {
      const existing = existingOptions.find(e => e.id === opt.id);
      return { ...opt, voted: existing?.voted ?? opt.voted };
    });

    const mergedPoll = { ...poll, options: mergedOptions };

    dispatch(
      'internalChat/messages/updateMessageFromCable',
      {
        channelId,
        message: {
          id: messageId,
          content_attributes: { ...existingAttrs, poll: mergedPoll },
        },
      },
      { root: true }
    );
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
