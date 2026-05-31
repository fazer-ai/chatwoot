import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import DisparosAPI from '../../api/disparos';

// Beta 0 "Disparador Cloud Shadow" store. The API is read-only / shadow: the
// list is fetched from the paginated index (`get`), individual records via
// `show`, and `create` appends a new draft. `dryRun`/`shadowRun` return their
// summary to the caller, and `getTargets` returns the persisted shadow targets
// to the caller — none of those reads are persisted in `records`, which holds
// only the disparo list.
export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isFetchingItem: false,
    isRunningDryRun: false,
    isShadowRunning: false,
    isFetchingTargets: false,
  },
};

export const getters = {
  getDisparos(_state) {
    return _state.records;
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  // Read-only listing of the account's disparos (paginated, capped server-side).
  // The index payload is a bare array, so it is committed wholesale to records.
  get: async function getDisparos({ commit }) {
    commit(types.SET_DISPARADOR_UI_FLAG, { isFetching: true });
    try {
      const response = await DisparosAPI.get();
      commit(types.SET_DISPAROS, response.data);
      return response.data;
    } catch (error) {
      const errorMessage = error?.response?.data?.error || error.message;
      throw new Error(errorMessage);
    } finally {
      commit(types.SET_DISPARADOR_UI_FLAG, { isFetching: false });
    }
  },

  show: async function showDisparo({ commit }, id) {
    commit(types.SET_DISPARADOR_UI_FLAG, { isFetchingItem: true });
    try {
      const response = await DisparosAPI.show(id);
      commit(types.UPDATE_DISPARO, response.data);
      return response.data;
    } catch (error) {
      const errorMessage = error?.response?.data?.error || error.message;
      throw new Error(errorMessage);
    } finally {
      commit(types.SET_DISPARADOR_UI_FLAG, { isFetchingItem: false });
    }
  },

  create: async function createDisparo({ commit }, disparoObj) {
    commit(types.SET_DISPARADOR_UI_FLAG, { isCreating: true });
    try {
      const response = await DisparosAPI.create({ disparo: disparoObj });
      commit(types.ADD_DISPARO, response.data);
      return response.data;
    } catch (error) {
      const errorMessage = error?.response?.data?.error || error.message;
      throw new Error(errorMessage);
    } finally {
      commit(types.SET_DISPARADOR_UI_FLAG, { isCreating: false });
    }
  },

  // Returns the considered-audience summary to the caller. The summary is a
  // computed read (eligible/skipped counts + cost) and is not stored in state.
  dryRun: async function dryRunDisparo({ commit }, id) {
    commit(types.SET_DISPARADOR_UI_FLAG, { isRunningDryRun: true });
    try {
      const response = await DisparosAPI.dryRun(id);
      return response.data;
    } catch (error) {
      const errorMessage = error?.response?.data?.error || error.message;
      throw new Error(errorMessage);
    } finally {
      commit(types.SET_DISPARADOR_UI_FLAG, { isRunningDryRun: false });
    }
  },

  // Persists the shadow target set and returns the run summary (total_targets,
  // eligible, skipped, created, updated) to the caller. The summary is a
  // computed read and is not stored in state.
  shadowRun: async function shadowRunDisparo({ commit }, { id }) {
    commit(types.SET_DISPARADOR_UI_FLAG, { isShadowRunning: true });
    try {
      const response = await DisparosAPI.shadowRun(id);
      return response.data;
    } catch (error) {
      const errorMessage = error?.response?.data?.error || error.message;
      throw new Error(errorMessage);
    } finally {
      commit(types.SET_DISPARADOR_UI_FLAG, { isShadowRunning: false });
    }
  },

  // Returns the persisted shadow targets (a bare, paginated array with SAFE
  // fields only — never a raw phone) to the caller. Targets are held in
  // component-local state, never in `records`.
  getTargets: async function getDisparoTargets({ commit }, { id, page = 1 }) {
    commit(types.SET_DISPARADOR_UI_FLAG, { isFetchingTargets: true });
    try {
      const response = await DisparosAPI.getTargets(id, page);
      return response.data;
    } catch (error) {
      const errorMessage = error?.response?.data?.error || error.message;
      throw new Error(errorMessage);
    } finally {
      commit(types.SET_DISPARADOR_UI_FLAG, { isFetchingTargets: false });
    }
  },
};

export const mutations = {
  [types.SET_DISPARADOR_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },

  [types.SET_DISPAROS]: MutationHelpers.set,
  [types.ADD_DISPARO]: MutationHelpers.create,
  [types.UPDATE_DISPARO]: MutationHelpers.update,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
