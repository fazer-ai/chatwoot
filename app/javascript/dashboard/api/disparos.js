/* global axios */
import ApiClient from './ApiClient';

class DisparosAPI extends ApiClient {
  constructor() {
    super('disparos', { accountScoped: true });
  }

  dryRun(id) {
    return axios.post(`${this.url}/${id}/dry_run`);
  }

  shadowRun(id) {
    return axios.post(`${this.url}/${id}/shadow_run`);
  }

  getTargets(id, page = 1) {
    return axios.get(`${this.url}/${id}/targets`, { params: { page } });
  }
}

export default new DisparosAPI();
