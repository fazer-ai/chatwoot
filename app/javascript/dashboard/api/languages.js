import ApiClient from './ApiClient';

class LanguagesApi extends ApiClient {
  constructor() {
    super('languages', { accountScoped: false });
  }
}

export default new LanguagesApi();
