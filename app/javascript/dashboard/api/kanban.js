/* global axios */
import ApiClient from './ApiClient';

class KanbanAPI extends ApiClient {
  constructor() {
    super('kanban', { accountScoped: true });
  }

  getConversations(params = {}) {
    return axios.get(this.url, { params });
  }

  moveConversation(conversationId, status) {
    return axios.put(`${this.url}/${conversationId}/move`, { status });
  }

  exportConversations(params = {}) {
    return axios.get(`${this.url}/export`, { params });
  }
}

export default new KanbanAPI();
