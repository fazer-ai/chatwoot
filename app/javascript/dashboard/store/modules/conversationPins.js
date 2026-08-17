import types from '../mutation-types';
import { throwErrorMessage } from 'dashboard/store/utils/api';

import ConversationApi from '../../api/inbox/conversation';

// Pins are personal, so the store holds the current agent's pins for the current account only, keyed by the
// conversation display id: { [conversationId]: pinnedAt }. Conversation objects stay untouched, which keeps
// the pin state correct no matter how a conversation entered the list (fetch, websocket, reopen).
const state = {
  records: {},
  uiFlags: {
    isFetching: false,
  },
};

export const getters = {
  getUIFlags: $state => $state.uiFlags,
  getRecords: $state => $state.records,
  isPinned: $state => conversationId => Boolean($state.records[conversationId]),
};

export const actions = {
  fetch: async ({ commit }) => {
    commit(types.SET_CONVERSATION_PINS_UI_FLAG, { isFetching: true });

    try {
      const { data } = await ConversationApi.fetchPins();
      commit(types.SET_CONVERSATION_PINS, data);
    } catch (error) {
      // A failed hydration only costs the pinned ordering, so it should not block the inbox from booting.
    } finally {
      commit(types.SET_CONVERSATION_PINS_UI_FLAG, { isFetching: false });
    }
  },

  pin: async ({ commit }, conversationId) => {
    try {
      const { data } = await ConversationApi.pin(conversationId);
      commit(types.SET_CONVERSATION_PIN, data);
    } catch (error) {
      throwErrorMessage(error);
    }
  },

  unpin: async ({ commit }, conversationId) => {
    try {
      await ConversationApi.unpin(conversationId);
      commit(types.REMOVE_CONVERSATION_PIN, {
        conversation_id: conversationId,
      });
    } catch (error) {
      throwErrorMessage(error);
    }
  },

  add: ({ commit }, data) => commit(types.SET_CONVERSATION_PIN, data),

  remove: ({ commit }, data) => commit(types.REMOVE_CONVERSATION_PIN, data),
};

export const mutations = {
  [types.SET_CONVERSATION_PINS_UI_FLAG]($state, data) {
    $state.uiFlags = { ...$state.uiFlags, ...data };
  },

  [types.SET_CONVERSATION_PINS]($state, data) {
    $state.records = (data || []).reduce(
      (records, { conversation_id: conversationId, pinned_at: pinnedAt }) => ({
        ...records,
        [conversationId]: pinnedAt,
      }),
      {}
    );
  },

  [types.SET_CONVERSATION_PIN](
    $state,
    { conversation_id: conversationId, pinned_at: pinnedAt }
  ) {
    $state.records = { ...$state.records, [conversationId]: pinnedAt };
  },

  [types.REMOVE_CONVERSATION_PIN]($state, { conversation_id: conversationId }) {
    const { [conversationId]: _removed, ...rest } = $state.records;
    $state.records = rest;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
