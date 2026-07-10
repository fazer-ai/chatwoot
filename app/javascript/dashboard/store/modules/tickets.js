import { throwErrorMessage } from 'dashboard/store/utils/api';
import * as types from '../mutation-types';
import TicketsAPI from '../../api/tickets';

// Feedback tickets (ClickUp integration). Meus Tickets consumes `records` +
// `meta`; the notifications side of the module keeps a lightweight
// `unreadCount` incremented by the ActionCable listener and reset when the
// operator visits the Meus Tickets route (see `markSeen`).
const state = {
  records: [],
  meta: {
    totalCount: 0,
    currentPage: 1,
    perPage: 25,
  },
  currentStatusFilter: null,
  unreadCount: 0,
  uiFlags: {
    fetchingList: false,
    fetchingItem: false,
    creatingItem: false,
    addingComment: false,
  },
};

const getters = {
  getRecords(_state) {
    return _state.records;
  },
  getMeta(_state) {
    return _state.meta;
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
  getUnreadCount(_state) {
    return _state.unreadCount;
  },
  getRecordById: _state => id =>
    _state.records.find(t => Number(t.id) === Number(id)) || null,
};

const actions = {
  create: async ({ commit }, payload) => {
    commit(types.default.SET_TICKETS_UI_FLAG, { creatingItem: true });
    try {
      const response = await TicketsAPI.create(payload);
      commit(types.default.SET_TICKETS_UI_FLAG, { creatingItem: false });
      commit(types.default.ADD_TICKET, response.data);
      return response.data;
    } catch (error) {
      commit(types.default.SET_TICKETS_UI_FLAG, { creatingItem: false });
      return throwErrorMessage(error);
    }
  },
  addComment: async ({ commit }, { id, comment }) => {
    commit(types.default.SET_TICKETS_UI_FLAG, { addingComment: true });
    try {
      await TicketsAPI.addComment(id, { comment });
      commit(types.default.SET_TICKETS_UI_FLAG, { addingComment: false });
    } catch (error) {
      commit(types.default.SET_TICKETS_UI_FLAG, { addingComment: false });
      return throwErrorMessage(error);
    }
    return true;
  },
  fetchAll: async ({ commit }, { page = 1, status } = {}) => {
    commit(types.default.SET_TICKETS_UI_FLAG, { fetchingList: true });
    try {
      const response = await TicketsAPI.fetchAll({ page, status });
      const { payload = [], meta = {} } = response.data || {};
      commit(types.default.SET_TICKETS, payload);
      commit(types.default.SET_TICKETS_META, {
        totalCount: meta.total_count ?? payload.length,
        currentPage: meta.current_page ?? page,
        perPage: meta.per_page ?? 25,
      });
      commit(types.default.SET_TICKETS_STATUS_FILTER, status || null);
      commit(types.default.SET_TICKETS_UI_FLAG, { fetchingList: false });
      return { payload, meta };
    } catch (error) {
      commit(types.default.SET_TICKETS_UI_FLAG, { fetchingList: false });
      return throwErrorMessage(error);
    }
  },
  fetch: async ({ commit }, id) => {
    commit(types.default.SET_TICKETS_UI_FLAG, { fetchingItem: true });
    try {
      const response = await TicketsAPI.fetch(id);
      commit(types.default.UPSERT_TICKET, response.data);
      commit(types.default.SET_TICKETS_UI_FLAG, { fetchingItem: false });
      return response.data;
    } catch (error) {
      commit(types.default.SET_TICKETS_UI_FLAG, { fetchingItem: false });
      return throwErrorMessage(error);
    }
  },
  // Called by the ActionCable listener when the ClickUp webhook applied a
  // status/response change. `notify` differentiates the loud transitions
  // (resolvido/restrição/encerrado + new resposta) from routine ones.
  updateFromWebsocket: ({ commit }, { ticket, notify }) => {
    commit(types.default.UPSERT_TICKET, ticket);
    if (notify) commit(types.default.INCREMENT_UNREAD_TICKETS);
  },
  markSeen: ({ commit }) => {
    commit(types.default.RESET_UNREAD_TICKETS);
  },
};

const mutations = {
  [types.default.SET_TICKETS_UI_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  [types.default.SET_TICKETS](_state, records) {
    _state.records = records;
  },
  [types.default.SET_TICKETS_META](_state, meta) {
    _state.meta = { ..._state.meta, ...meta };
  },
  [types.default.SET_TICKETS_STATUS_FILTER](_state, status) {
    _state.currentStatusFilter = status;
  },
  [types.default.ADD_TICKET](_state, ticket) {
    // Push newest to the front so the operator sees the ticket they just
    // filed at the top of Meus Tickets on their next visit.
    _state.records = [
      ticket,
      ..._state.records.filter(t => t.id !== ticket.id),
    ];
  },
  [types.default.UPSERT_TICKET](_state, ticket) {
    const idx = _state.records.findIndex(t => t.id === ticket.id);
    if (idx === -1) {
      _state.records = [ticket, ..._state.records];
    } else {
      const next = [..._state.records];
      next[idx] = { ..._state.records[idx], ...ticket };
      _state.records = next;
    }
  },
  [types.default.INCREMENT_UNREAD_TICKETS](_state) {
    _state.unreadCount += 1;
  },
  [types.default.RESET_UNREAD_TICKETS](_state) {
    _state.unreadCount = 0;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
