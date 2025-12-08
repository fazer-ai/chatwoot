/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class PreferencesAPI extends ApiClient {
  constructor() {
    super('kanban/account_user_preferences', {
      accountScoped: true,
      apiVersion: 'v1',
    });
  }

  update(preferences) {
    return axios.put(this.url, { preferences });
  }
}

export default new PreferencesAPI();
