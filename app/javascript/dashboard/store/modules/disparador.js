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
  // GAP B: the latest dry-run snapshot id per disparo. shadow_run must reference
  // the snapshot the operator approved via a dry-run, so we hold the id keyed by
  // disparo id (a disparo's shadow-run is only enabled once a snapshot exists).
  snapshotByDisparo: {},
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
  // Returns the approved dry-run snapshot id for a disparo, or undefined when no
  // dry-run has been run (or it was invalidated by a 422). Index.vue reads this
  // to gate + drive the shadow-run.
  getSnapshotId: _state => id => _state.snapshotByDisparo[id],
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
  // GAP B: it also carries a snapshot_id, which we DO persist (per disparo) so
  // shadow_run can reference the snapshot the operator just approved.
  dryRun: async function dryRunDisparo({ commit }, id) {
    commit(types.SET_DISPARADOR_UI_FLAG, { isRunningDryRun: true });
    try {
      const response = await DisparosAPI.dryRun(id);
      if (response.data?.snapshot_id) {
        commit(types.SET_DISPARO_SNAPSHOT, {
          id,
          snapshotId: response.data.snapshot_id,
        });
      }
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
  // GAP B: shadow_run REQUIRES the snapshot_id from the approved dry-run. On a
  // 422 (snapshot missing/expired/config-changed) we drop the held snapshot so
  // the UI re-gates on a fresh dry-run, then re-throw for the caller's toast.
  shadowRun: async function shadowRunDisparo({ commit }, { id, snapshotId }) {
    commit(types.SET_DISPARADOR_UI_FLAG, { isShadowRunning: true });
    try {
      const response = await DisparosAPI.shadowRun(id, snapshotId);
      return response.data;
    } catch (error) {
      const errorMessage = error?.response?.data?.error || error.message;
      if (errorMessage === 'invalid_shadow_run') {
        commit(types.CLEAR_DISPARO_SNAPSHOT, id);
      }
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

  [types.SET_DISPARO_SNAPSHOT](_state, { id, snapshotId }) {
    _state.snapshotByDisparo = {
      ..._state.snapshotByDisparo,
      [id]: snapshotId,
    };
  },

  [types.CLEAR_DISPARO_SNAPSHOT](_state, id) {
    const next = { ..._state.snapshotByDisparo };
    delete next[id];
    _state.snapshotByDisparo = next;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
