/* global axios */
import ApiClient from './ApiClient';

class InternalChatMessagesAPI extends ApiClient {
  constructor() {
    super('internal_chat/channels', { accountScoped: true });
  }

  getMessages(channelId, params = {}) {
    return axios.get(`${this.url}/${channelId}/messages`, { params });
  }

  createMessage(channelId, data) {
    return axios.post(`${this.url}/${channelId}/messages`, data);
  }

  updateMessage(channelId, messageId, data) {
    return axios.patch(`${this.url}/${channelId}/messages/${messageId}`, data);
  }

  deleteMessage(channelId, messageId) {
    return axios.delete(`${this.url}/${channelId}/messages/${messageId}`);
  }

  getThread(channelId, messageId) {
    return axios.get(`${this.url}/${channelId}/messages/${messageId}/thread`);
  }

  pinMessage(channelId, messageId) {
    return axios.post(`${this.url}/${channelId}/messages/${messageId}/pin`);
  }

  unpinMessage(channelId, messageId) {
    return axios.delete(`${this.url}/${channelId}/messages/${messageId}/unpin`);
  }

  addReaction(messageId, emoji) {
    const baseUrl = this.url.replace('/channels', '');
    return axios.post(`${baseUrl}/messages/${messageId}/reactions`, {
      emoji,
    });
  }

  removeReaction(messageId, reactionId) {
    const baseUrl = this.url.replace('/channels', '');
    return axios.delete(
      `${baseUrl}/messages/${messageId}/reactions/${reactionId}`
    );
  }
}

export default new InternalChatMessagesAPI();
