/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class BoardsAPI extends ApiClient {
  constructor() {
    super('kanban/boards', { accountScoped: true, apiVersion: 'v1' });
  }

  get(params) {
    return axios.get(this.url, { params });
  }

  getSteps(boardId, { agentId, inboxId } = {}) {
    const params = {};
    if (agentId && agentId !== 'all') params.agent_id = agentId;
    if (inboxId && inboxId !== 'all') params.inbox_id = inboxId;
    return axios.get(`${this.url}/${boardId}/steps`, { params });
  }

  updateStep(boardId, stepId, data) {
    return axios.put(`${this.url}/${boardId}/steps/${stepId}`, data);
  }

  deleteStep(boardId, stepId) {
    return axios.delete(`${this.url}/${boardId}/steps/${stepId}`);
  }

  createStep(boardId, data) {
    return axios.post(`${this.url}/${boardId}/steps`, data);
  }

  create(data) {
    return axios.post(this.url, { board: data });
  }

  update(boardId, data) {
    return axios.put(`${this.url}/${boardId}`, data);
  }

  updateAgents(boardId, agentIds) {
    return axios.post(`${this.url}/${boardId}/update_agents`, {
      agent_ids: agentIds,
    });
  }

  updateInboxes(boardId, inboxIds) {
    return axios.post(`${this.url}/${boardId}/update_inboxes`, {
      inbox_ids: inboxIds,
    });
  }

  getConversations(boardId, query) {
    return axios.get(`${this.url}/${boardId}/conversations`, {
      params: { q: query },
    });
  }

  toggleFavorite(boardId) {
    return axios.post(`${this.url}/${boardId}/toggle_favorite`);
  }
}

export default new BoardsAPI();
