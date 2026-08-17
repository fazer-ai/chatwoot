import types from '../mutation-types';
import { throwErrorMessage } from 'dashboard/store/utils/api';

import ConversationApi from '../../api/inbox/conversation';

// Pins are personal, so the store holds the current agent's pins for the current account only, keyed by the
// conversation display id: { [conversationId]: pinnedAt }. Conversation objects stay untouched, which keeps
// the pin state correct no matter how a conversation entered the list (fetch, websocket, reopen).
// `appliedAt` is the version of the last pin/unpin applied per conversation. Both events for the same pin
// carry that pin's `pinned_at`, and the broadcast jobs are asynchronous, so a `pinned` event that lost the
// race with the `unpin` right after it would otherwise resurrect a pin the server no longer has.
const state = {
  records: {},
  appliedAt: {},
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

  unpin: async ({ commit, state: $state }, conversationId) => {
    const pinnedAt = $state.records[conversationId];
    try {
      await ConversationApi.unpin(conversationId);
      commit(types.REMOVE_CONVERSATION_PIN, {
        conversation_id: conversationId,
        pinned_at: pinnedAt,
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

  [types.SET_CONVERSATION_PINS]($state, { pins, synced_at: syncedAt }) {
    const records = (pins || []).reduce(
      (acc, { conversation_id: conversationId, pinned_at: pinnedAt }) => ({
        ...acc,
        [conversationId]: pinnedAt,
      }),
      {}
    );

    // An event applied after the server built the snapshot is newer than it, in both directions: a pin the
    // snapshot could not have seen has to survive, and one it still lists must not come back.
    Object.entries($state.appliedAt).forEach(([conversationId, appliedAt]) => {
      if (syncedAt === undefined || appliedAt <= syncedAt) return;

      const local = $state.records[conversationId];
      if (local === undefined) delete records[conversationId];
      else records[conversationId] = local;
    });

    $state.records = records;
    // Versions of conversations that are no longer pinned are kept, so a later snapshot cannot re-arm an
    // event that was already superseded.
    $state.appliedAt = { ...$state.appliedAt, ...records };
  },

  [types.SET_CONVERSATION_PIN](
    $state,
    { conversation_id: conversationId, pinned_at: pinnedAt }
  ) {
    const appliedAt = $state.appliedAt[conversationId];
    // Re-applying the pin currently held is a no-op; anything else at or below the applied version is an
    // event a newer pin or unpin already superseded.
    const isSupersededPin =
      appliedAt !== undefined &&
      pinnedAt <= appliedAt &&
      $state.records[conversationId] !== pinnedAt;
    if (isSupersededPin) return;

    $state.records = { ...$state.records, [conversationId]: pinnedAt };
    $state.appliedAt = { ...$state.appliedAt, [conversationId]: pinnedAt };
  },

  [types.REMOVE_CONVERSATION_PIN](
    $state,
    { conversation_id: conversationId, pinned_at: pinnedAt }
  ) {
    const appliedAt = $state.appliedAt[conversationId];
    const isSupersededUnpin =
      pinnedAt !== undefined && appliedAt !== undefined && pinnedAt < appliedAt;
    if (isSupersededUnpin) return;

    const { [conversationId]: _removed, ...rest } = $state.records;
    $state.records = rest;
    $state.appliedAt = {
      ...$state.appliedAt,
      [conversationId]: Math.max(pinnedAt ?? 0, appliedAt ?? 0),
    };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
