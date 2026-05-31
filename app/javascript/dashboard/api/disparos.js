/* global axios */
import ApiClient from './ApiClient';

class DisparosAPI extends ApiClient {
  constructor() {
    super('disparos', { accountScoped: true });
  }

  dryRun(id) {
    return axios.post(`${this.url}/${id}/dry_run`);
  }

  // GAP B: shadow_run must reference the snapshot from the approved dry-run.
  // The backend 422s when snapshot_id is missing/expired/config-changed.
  shadowRun(id, snapshotId) {
    return axios.post(`${this.url}/${id}/shadow_run`, {
      snapshot_id: snapshotId,
    });
  }

  getTargets(id, page = 1) {
    return axios.get(`${this.url}/${id}/targets`, { params: { page } });
  }
}

export default new DisparosAPI();
