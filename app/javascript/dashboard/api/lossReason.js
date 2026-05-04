import ApiClient from './ApiClient';

class LossReasonAPI extends ApiClient {
  constructor() {
    super('loss_reasons', { accountScoped: true });
  }
}

export default new LossReasonAPI();
