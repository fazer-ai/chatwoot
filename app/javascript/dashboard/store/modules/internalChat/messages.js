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
      if (params.before) {
        commit('PREPEND_MESSAGES', { channelId, messages });
      } else if (params.after) {
        commit('APPEND_MESSAGES', { channelId, messages });
      } else {
        commit('SET_MESSAGES', { channelId, messages });
      }
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

  fetchThread: async ({ commit }, { channelId, messageId }) => {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const response = await InternalChatMessagesAPI.getThread(
        channelId,
        messageId
      );
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  sendThreadReply: async ({ commit }, { channelId, parentMessageId, data }) => {
    commit('SET_UI_FLAG', { isSending: true });
    try {
      const response = await InternalChatMessagesAPI.createMessage(channelId, {
        ...data,
        parent_id: parentMessageId,
      });
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    } finally {
      commit('SET_UI_FLAG', { isSending: false });
    }
  },

  pinMessage: async ({ commit }, { channelId, messageId }) => {
    try {
      const response = await InternalChatMessagesAPI.pinMessage(
        channelId,
        messageId
      );
      commit('UPDATE_MESSAGE', { channelId, message: response.data });
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    }
  },

  unpinMessage: async ({ commit }, { channelId, messageId }) => {
    try {
      const response = await InternalChatMessagesAPI.unpinMessage(
        channelId,
        messageId
      );
      commit('UPDATE_MESSAGE', { channelId, message: response.data });
      return response.data;
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

  PREPEND_MESSAGES(_state, { channelId, messages }) {
    const existing = _state.records[channelId] || [];
    const existingIds = new Set(existing.map(m => m.id));
    const newMessages = messages.filter(m => !existingIds.has(m.id));
    _state.records = {
      ..._state.records,
      [channelId]: [...newMessages, ...existing],
    };
  },

  APPEND_MESSAGES(_state, { channelId, messages }) {
    const existing = _state.records[channelId] || [];
    const existingIds = new Set(existing.map(m => m.id));
    const newMessages = messages.filter(m => !existingIds.has(m.id));
    _state.records = {
      ..._state.records,
      [channelId]: [...existing, ...newMessages],
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
    const messages = _state.records[channelId];
    if (!messages) return;
    const index = messages.findIndex(m => m.id === messageId);
    if (index !== -1) {
      const updated = [...messages];
      updated[index] = {
        ...updated[index],
        content_attributes: {
          ...updated[index].content_attributes,
          deleted: true,
        },
      };
      _state.records = {
        ..._state.records,
        [channelId]: updated,
      };
    }
  },

  ADD_REACTION(_state, { channelId, messageId, reaction }) {
    const existing = _state.records[channelId] || [];
    const index = existing.findIndex(m => m.id === messageId);
    if (index > -1) {
      const message = existing[index];
      const currentReactions = message.reactions || [];
      if (currentReactions.some(r => r.id === reaction.id)) return;
      const reactions = [...currentReactions, reaction];
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
