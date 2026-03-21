/* global axios */
import ApiClient from './ApiClient';

class InternalChatDraftsAPI extends ApiClient {
  constructor() {
    super('internal_chat/drafts', { accountScoped: true });
  }

  getDrafts() {
    return axios.get(this.url);
  }

  saveDraft(data) {
    return axios.post(this.url, data);
  }

  deleteDraft(draftId) {
    return axios.delete(`${this.url}/${draftId}`);
  }
}

export default new InternalChatDraftsAPI();
