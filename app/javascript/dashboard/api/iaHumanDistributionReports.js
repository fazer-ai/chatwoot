/* global axios */
import ApiClient from './ApiClient';

class IaHumanDistributionReportsAPI extends ApiClient {
  constructor() {
    super('ia_human_distribution_reports', {
      accountScoped: true,
      apiVersion: 'v2',
    });
  }

  fetch({ from, to, inboxId }) {
    return axios.get(this.url, {
      params: {
        from,
        to,
        inbox_id: inboxId || undefined,
      },
    });
  }
}

export default new IaHumanDistributionReportsAPI();
