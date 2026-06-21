import OperationsNotificationsAPI from '../../api/operationsNotifications';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const state = {
  // Last 10 visible notifications (acked or not) — for the bell panel.
  records: [],
  // Subset that the current user has NOT acknowledged yet — drives the modal.
  pending: [],
  uiFlags: {
    fetchingList: false,
    fetchingPending: false,
    isAcknowledging: false,
  },
};

const getters = {
  getRecords: _state => _state.records,
  getPending: _state => _state.pending,
  getUIFlags: _state => _state.uiFlags,
  hasPending: _state => _state.pending.length > 0,
  // The bell badge — count of unacked items the user can still see.
  getUnreadCount: _state => _state.pending.length,
};

const actions = {
  async fetchList({ commit }) {
    commit('SET_UI_FLAG', { fetchingList: true });
    try {
      const { data } = await OperationsNotificationsAPI.get();
      commit('SET_RECORDS', data?.data?.payload || []);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { fetchingList: false });
    }
  },

  // Called on app boot + every 30s. Updates `pending` so the modal opens
  // whenever a new notification appears.
  async fetchPending({ commit }) {
    commit('SET_UI_FLAG', { fetchingPending: true });
    try {
      const { data } = await OperationsNotificationsAPI.pending();
      commit('SET_PENDING', data?.data?.payload || []);
    } catch (error) {
      // Swallow polling errors silently — surfacing a toast on every tick
      // would spam the user during transient network issues.
      // eslint-disable-next-line no-console
      console.error('[operationsNotifications] pending fetch failed', error);
    } finally {
      commit('SET_UI_FLAG', { fetchingPending: false });
    }
  },

  // Acknowledges and locally removes from `pending` so the modal advances
  // to the next item (or closes when empty).
  async acknowledge({ commit, state: _state }, id) {
    commit('SET_UI_FLAG', { isAcknowledging: true });
    try {
      await OperationsNotificationsAPI.acknowledge(id);
      commit('REMOVE_PENDING', id);
      // Mirror the ack on the bell-list record too (so the badge updates).
      const acked = _state.records.find(r => r.id === id);
      if (acked) {
        commit('UPDATE_RECORD', {
          ...acked,
          acknowledged_at: Math.floor(Date.now() / 1000),
        });
      }
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isAcknowledging: false });
    }
  },
};

const mutations = {
  SET_UI_FLAG(_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  SET_RECORDS(_state, data) {
    _state.records = data;
  },
  SET_PENDING(_state, data) {
    _state.pending = data;
  },
  REMOVE_PENDING(_state, id) {
    _state.pending = _state.pending.filter(n => n.id !== id);
  },
  UPDATE_RECORD(_state, record) {
    _state.records = _state.records.map(r => (r.id === record.id ? record : r));
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
