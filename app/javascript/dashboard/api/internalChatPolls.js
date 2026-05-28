/* global axios */
import ApiClient from './ApiClient';

class InternalChatPollsAPI extends ApiClient {
  constructor() {
    super('internal_chat/polls', { accountScoped: true });
  }

  createPoll(data) {
    return axios.post(this.url, data);
  }

  vote(pollId, optionId) {
    return axios.post(`${this.url}/${pollId}/vote`, { option_id: optionId });
  }

  unvote(pollId, optionId) {
    return axios.delete(`${this.url}/${pollId}/vote`, {
      params: { option_id: optionId },
    });
  }
}

export default new InternalChatPollsAPI();
