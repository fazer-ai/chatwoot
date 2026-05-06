/* global axios */
import ApiClient from './ApiClient';

class AccountAPI extends ApiClient {
  constructor() {
    super('', { accountScoped: true });
  }

  createAccount(data) {
    return axios.post(`${this.apiVersion}/accounts`, data);
  }

  async getCacheKeys() {
    const response = await axios.get(
      `/api/v1/accounts/${this.accountIdFromRoute}/cache_keys`
    );
    return response.data.cache_keys;
  }

  enableFeature(feature) {
    return axios.post(
      `/api/v1/accounts/${this.accountIdFromRoute}/enable_feature`,
      { feature }
    );
  }
}

export default new AccountAPI();
