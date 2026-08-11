/* global axios */
import ApiClient from './ApiClient';

class MetaTemplatesAPI extends ApiClient {
  constructor() {
    super('meta_templates', { accountScoped: true, apiVersion: 'v2' });
  }

  // Fetches the cached templates for a given Cloud WhatsApp inbox.
  // Backend returns `{ inbox, templates, last_synced_at }`.
  fetch({ inboxId }) {
    return axios.get(this.url, { params: { inbox_id: inboxId } });
  }

  // Triggers an inline sync with Meta and returns the fresh payload.
  // Same shape as `fetch`.
  sync({ inboxId }) {
    return axios.post(
      `${this.url}/sync`,
      {},
      { params: { inbox_id: inboxId } }
    );
  }
}

export default new MetaTemplatesAPI();
