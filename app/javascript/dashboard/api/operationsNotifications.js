/* global axios */
import ApiClient from './ApiClient';

class OperationsNotificationsApi extends ApiClient {
  constructor() {
    super('operations_notifications', { accountScoped: true });
  }

  // List of pending (not yet acknowledged) notifications for the current user
  // — what feeds the on-login modal and the 30s polling.
  pending() {
    return axios.get(`${this.url}/pending`);
  }

  // Mark a notification as seen by the current user. Backend captures the
  // request ip + user_agent for the super-admin report. Idempotent.
  acknowledge(id) {
    return axios.post(`${this.url}/${id}/acknowledge`);
  }
}

export default new OperationsNotificationsApi();
