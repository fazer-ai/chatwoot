/* global axios */
import ApiClient from './ApiClient';

class InternalChatDraftsAPI extends ApiClient {
  constructor() {
    super('internal_chat', { accountScoped: true });
  }

  getDrafts() {
    return axios.get(`${this.url}/drafts`);
  }

  saveDraft(channelId, data) {
    return axios.patch(`${this.url}/channels/${channelId}/draft`, data);
  }

  deleteDraft(channelId, { parentId } = {}) {
    return axios.delete(`${this.url}/channels/${channelId}/draft`, {
      params: { parent_id: parentId },
    });
  }
}

export default new InternalChatDraftsAPI();
