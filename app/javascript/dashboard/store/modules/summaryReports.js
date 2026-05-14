import SummaryReportsAPI from 'dashboard/api/summaryReports';
import camelcaseKeys from 'camelcase-keys';

const typeMap = {
  inbox: {
    flagKey: 'isFetchingInboxSummaryReports',
    apiMethod: 'getInboxReports',
    mutationKey: 'setInboxSummaryReport',
  },
  agent: {
    flagKey: 'isFetchingAgentSummaryReports',
    apiMethod: 'getAgentReports',
    mutationKey: 'setAgentSummaryReport',
  },
  team: {
    flagKey: 'isFetchingTeamSummaryReports',
    apiMethod: 'getTeamReports',
    mutationKey: 'setTeamSummaryReport',
  },
  label: {
    flagKey: 'isFetchingLabelSummaryReports',
    apiMethod: 'getLabelReports',
    mutationKey: 'setLabelSummaryReport',
  },
  funnel: {
    flagKey: 'isFetchingFunnelSummaryReports',
    apiMethod: 'getFunnelReports',
    mutationKey: 'setFunnelSummaryReport',
  },
  funnelConversion: {
    flagKey: 'isFetchingFunnelConversionReports',
    apiMethod: 'getFunnelConversionReports',
    mutationKey: 'setFunnelConversionReport',
  },
};

async function fetchSummaryReports(type, params, { commit }) {
  const config = typeMap[type];
  if (!config) return;

  let error = null;
  try {
    commit('setUIFlags', { [config.flagKey]: true });
    const response = await SummaryReportsAPI[config.apiMethod](params);
    commit(config.mutationKey, camelcaseKeys(response.data, { deep: true }));
  } catch (e) {
    error = e;
  } finally {
    commit('setUIFlags', { [config.flagKey]: false });
  }
  if (error) throw error;
}

export const initialState = {
  inboxSummaryReports: [],
  agentSummaryReports: [],
  teamSummaryReports: [],
  labelSummaryReports: [],
  funnelSummaryReports: [],
  funnelConversionReport: { stages: [], kpis: {} },
  uiFlags: {
    isFetchingInboxSummaryReports: false,
    isFetchingAgentSummaryReports: false,
    isFetchingTeamSummaryReports: false,
    isFetchingLabelSummaryReports: false,
    isFetchingFunnelSummaryReports: false,
    isFetchingFunnelConversionReports: false,
  },
};

export const getters = {
  getInboxSummaryReports(state) {
    return state.inboxSummaryReports;
  },
  getAgentSummaryReports(state) {
    return state.agentSummaryReports;
  },
  getTeamSummaryReports(state) {
    return state.teamSummaryReports;
  },
  getLabelSummaryReports(state) {
    return state.labelSummaryReports;
  },
  getFunnelSummaryReports(state) {
    return state.funnelSummaryReports;
  },
  getFunnelConversionReport(state) {
    return state.funnelConversionReport;
  },
  getUIFlags(state) {
    return state.uiFlags;
  },
};

export const actions = {
  fetchInboxSummaryReports({ commit }, params) {
    return fetchSummaryReports('inbox', params, { commit });
  },

  fetchAgentSummaryReports({ commit }, params) {
    return fetchSummaryReports('agent', params, { commit });
  },

  fetchTeamSummaryReports({ commit }, params) {
    return fetchSummaryReports('team', params, { commit });
  },

  fetchLabelSummaryReports({ commit }, params) {
    return fetchSummaryReports('label', params, { commit });
  },

  fetchFunnelSummaryReports({ commit }, params) {
    return fetchSummaryReports('funnel', params, { commit });
  },

  fetchFunnelConversionReports({ commit }, params) {
    return fetchSummaryReports('funnelConversion', params, { commit });
  },
};

export const mutations = {
  setInboxSummaryReport(state, data) {
    state.inboxSummaryReports = data;
  },
  setAgentSummaryReport(state, data) {
    state.agentSummaryReports = data;
  },
  setTeamSummaryReport(state, data) {
    state.teamSummaryReports = data;
  },
  setLabelSummaryReport(state, data) {
    state.labelSummaryReports = data;
  },
  setFunnelSummaryReport(state, data) {
    state.funnelSummaryReports = data;
  },
  setFunnelConversionReport(state, data) {
    state.funnelConversionReport = data;
  },
  setUIFlags(state, uiFlag) {
    state.uiFlags = { ...state.uiFlags, ...uiFlag };
  },
};

export default {
  namespaced: true,
  state: initialState,
  getters,
  actions,
  mutations,
};
