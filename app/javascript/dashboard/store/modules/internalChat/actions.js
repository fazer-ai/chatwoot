import InternalChatChannelsAPI from '../../../api/internalChatChannels';
import { throwErrorMessage } from 'dashboard/store/utils/api';

export const actions = {
  get: async ({ commit }) => {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const [channelsResponse, categoriesResponse] = await Promise.all([
        InternalChatChannelsAPI.get(),
        InternalChatChannelsAPI.getCategories(),
      ]);
      commit('SET_CHANNELS', channelsResponse.data);
      commit('SET_CATEGORIES', categoriesResponse.data);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  create: async ({ commit }, channelData) => {
    commit('SET_UI_FLAG', { isCreating: true });
    try {
      const response = await InternalChatChannelsAPI.create(channelData);
      commit('ADD_CHANNEL', response.data);
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    } finally {
      commit('SET_UI_FLAG', { isCreating: false });
    }
  },

  update: async ({ commit }, { channelId, ...data }) => {
    try {
      const response = await InternalChatChannelsAPI.update(channelId, data);
      commit('UPDATE_CHANNEL', response.data);
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    }
  },

  delete: async ({ commit }, channelId) => {
    try {
      await InternalChatChannelsAPI.delete(channelId);
      commit('DELETE_CHANNEL', channelId);
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    }
  },

  archive: async ({ commit }, channelId) => {
    try {
      const response = await InternalChatChannelsAPI.archive(channelId);
      commit('UPDATE_CHANNEL', response.data);
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    }
  },

  unarchive: async ({ commit }, channelId) => {
    try {
      const response = await InternalChatChannelsAPI.unarchive(channelId);
      commit('UPDATE_CHANNEL', response.data);
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    }
  },

  toggleMute: async ({ commit, state }, channelId) => {
    const channel = state.records[channelId];
    if (!channel) return;
    const updatedChannel = { ...channel, muted: !channel.muted };
    commit('UPDATE_CHANNEL', updatedChannel);
  },

  toggleFavorite: async ({ commit, state }, channelId) => {
    const channel = state.records[channelId];
    if (!channel) return;
    const updatedChannel = { ...channel, favorited: !channel.favorited };
    commit('UPDATE_CHANNEL', updatedChannel);
  },

  markRead: async ({ commit }, channelId) => {
    try {
      await InternalChatChannelsAPI.markRead(channelId);
      commit('UPDATE_CHANNEL', { id: channelId, unread_count: 0 });
    } catch (error) {
      throwErrorMessage(error);
    }
  },

  markUnread: async ({ commit }, { channelId, messageId }) => {
    try {
      await InternalChatChannelsAPI.markUnread(channelId, messageId);
      commit('UPDATE_CHANNEL', { id: channelId, unread_count: 1 });
    } catch (error) {
      throwErrorMessage(error);
    }
  },

  setActiveChannel: ({ commit }, channelId) => {
    commit('SET_ACTIVE_CHANNEL', channelId);
  },

  addChannel: ({ commit }, channel) => {
    commit('ADD_CHANNEL', channel);
  },

  updateChannel: ({ commit }, channel) => {
    commit('UPDATE_CHANNEL', channel);
  },
};

export default actions;
