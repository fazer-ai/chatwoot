/* global axios */
import ApiClient from './ApiClient';

class ReleasesApi extends ApiClient {
  constructor() {
    super('releases', { accountScoped: false });
  }

  // eslint-disable-next-line class-methods-use-this
  dismissRelease(tag) {
    return axios.post('/api/v1/profile/dismiss_release', { tag });
  }
}

export default new ReleasesApi();
