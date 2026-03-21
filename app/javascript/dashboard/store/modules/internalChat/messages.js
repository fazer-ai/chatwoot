import InternalChatMessagesAPI from '../../../api/internalChatMessages';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const state = {
  records: {},
  uiFlags: {
    isFetching: false,
    isSending: false,
  },
};

const getters = {
  getMessages: _state => channelId => {
    return _state.records[channelId] || [];
  },

  getMessageById: _state => (channelId, messageId) => {
    const messages = _state.records[channelId] || [];
    return messages.find(m => m.id === messageId) || null;
  },

  getUIFlags: _state => {
    return _state.uiFlags;
  },
};

const actions = {
  fetchMessages: async ({ commit }, { channelId, params = {} }) => {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const response = await InternalChatMessagesAPI.getMessages(
        channelId,
        params
      );
      const messages = response.data.messages || response.data;
      commit('SET_MESSAGES', { channelId, messages });
      return messages;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  sendMessage: async ({ commit }, { channelId, data }) => {
    commit('SET_UI_FLAG', { isSending: true });
    try {
      const response = await InternalChatMessagesAPI.createMessage(
        channelId,
        data
      );
      commit('ADD_MESSAGE', { channelId, message: response.data });
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    } finally {
      commit('SET_UI_FLAG', { isSending: false });
    }
  },

  updateMessage: async ({ commit }, { channelId, messageId, data }) => {
    try {
      const response = await InternalChatMessagesAPI.updateMessage(
        channelId,
        messageId,
        data
      );
      commit('UPDATE_MESSAGE', { channelId, message: response.data });
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    }
  },

  deleteMessage: async ({ commit }, { channelId, messageId }) => {
    try {
      await InternalChatMessagesAPI.deleteMessage(channelId, messageId);
      commit('DELETE_MESSAGE', { channelId, messageId });
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    }
  },

  addReaction: async ({ commit }, { channelId, messageId, emoji }) => {
    try {
      const response = await InternalChatMessagesAPI.addReaction(
        messageId,
        emoji
      );
      commit('ADD_REACTION', {
        channelId,
        messageId,
        reaction: response.data,
      });
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    }
  },

  removeReaction: async ({ commit }, { channelId, messageId, reactionId }) => {
    try {
      await InternalChatMessagesAPI.removeReaction(messageId, reactionId);
      commit('REMOVE_REACTION', { channelId, messageId, reactionId });
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    }
  },

  addMessageFromCable: ({ commit }, { channelId, message }) => {
    commit('ADD_MESSAGE', { channelId, message });
  },

  updateMessageFromCable: ({ commit }, { channelId, message }) => {
    commit('UPDATE_MESSAGE', { channelId, message });
  },

  deleteMessageFromCable: ({ commit }, { channelId, messageId }) => {
    commit('DELETE_MESSAGE', { channelId, messageId });
  },

  addReactionFromCable: ({ commit }, { channelId, messageId, reaction }) => {
    commit('ADD_REACTION', { channelId, messageId, reaction });
  },

  removeReactionFromCable: (
    { commit },
    { channelId, messageId, reactionId }
  ) => {
    commit('REMOVE_REACTION', { channelId, messageId, reactionId });
  },
};

const mutations = {
  SET_MESSAGES(_state, { channelId, messages }) {
    _state.records = {
      ..._state.records,
      [channelId]: messages,
    };
  },

  ADD_MESSAGE(_state, { channelId, message }) {
    const existing = _state.records[channelId] || [];
    const alreadyExists = existing.some(m => m.id === message.id);
    if (!alreadyExists) {
      _state.records = {
        ..._state.records,
        [channelId]: [...existing, message],
      };
    }
  },

  UPDATE_MESSAGE(_state, { channelId, message }) {
    const existing = _state.records[channelId] || [];
    const index = existing.findIndex(m => m.id === message.id);
    if (index > -1) {
      const updated = [...existing];
      updated[index] = { ...existing[index], ...message };
      _state.records = {
        ..._state.records,
        [channelId]: updated,
      };
    }
  },

  DELETE_MESSAGE(_state, { channelId, messageId }) {
    const existing = _state.records[channelId] || [];
    _state.records = {
      ..._state.records,
      [channelId]: existing.filter(m => m.id !== messageId),
    };
  },

  ADD_REACTION(_state, { channelId, messageId, reaction }) {
    const existing = _state.records[channelId] || [];
    const index = existing.findIndex(m => m.id === messageId);
    if (index > -1) {
      const message = existing[index];
      const reactions = [...(message.reactions || []), reaction];
      const updated = [...existing];
      updated[index] = { ...message, reactions };
      _state.records = {
        ..._state.records,
        [channelId]: updated,
      };
    }
  },

  REMOVE_REACTION(_state, { channelId, messageId, reactionId }) {
    const existing = _state.records[channelId] || [];
    const index = existing.findIndex(m => m.id === messageId);
    if (index > -1) {
      const message = existing[index];
      const reactions = (message.reactions || []).filter(
        r => r.id !== reactionId
      );
      const updated = [...existing];
      updated[index] = { ...message, reactions };
      _state.records = {
        ..._state.records,
        [channelId]: updated,
      };
    }
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
