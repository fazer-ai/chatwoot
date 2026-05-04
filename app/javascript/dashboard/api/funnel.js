/* global axios */
import ApiClient from './ApiClient';

class FunnelAPI extends ApiClient {
  constructor() {
    super('funnel', { accountScoped: true });
  }

  // Override the default singular `show` and use a custom shape.
  get(params = {}) {
    const search = new URLSearchParams();
    Object.entries(params).forEach(([key, value]) => {
      if (value === undefined || value === null || value === '') return;
      search.append(key, value);
    });
    const query = search.toString();
    const url = query ? `${this.url}?${query}` : this.url;
    return axios.get(url);
  }

  move({ conversationId, stage, reason, source = 'web', lossReasonId }) {
    return axios.post(`${this.url}/move`, {
      conversation_id: conversationId,
      stage,
      reason,
      source,
      loss_reason_id: lossReasonId,
    });
  }

  history(conversationId) {
    return axios.get(`${this.url}/history`, {
      params: { conversation_id: conversationId },
    });
  }
}

export default new FunnelAPI();
