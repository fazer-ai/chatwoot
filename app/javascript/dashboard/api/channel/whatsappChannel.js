/* global axios */
import ApiClient from '../ApiClient';

class WhatsappChannel extends ApiClient {
  constructor() {
    super('whatsapp', { accountScoped: true });
  }

  createEmbeddedSignup(params) {
    return axios.post(`${this.baseUrl()}/whatsapp/authorization`, params);
  }

  postEmbeddedSignupAuthorization({ inboxId, ...params }) {
    return axios.post(`${this.baseUrl()}/whatsapp/authorization`, {
      ...params,
      inbox_id: inboxId,
    });
  }

  // The provider catalog the session setup form renders itself from: which providers
  // this account may pick, what each one asks for and what it can do once connected.
  getSessionProviders() {
    return axios.get(`${this.baseUrl()}/whatsapp/session_providers`);
  }
}

export default new WhatsappChannel();
