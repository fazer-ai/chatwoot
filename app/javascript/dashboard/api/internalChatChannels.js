/* global axios */
import ApiClient from './ApiClient';

class InternalChatChannelsAPI extends ApiClient {
  constructor() {
    super('internal_chat/channels', { accountScoped: true });
  }

  getCategories() {
    return axios.get(`${this.url.replace('/channels', '/categories')}`);
  }

  createCategory(data) {
    return axios.post(`${this.url.replace('/channels', '/categories')}`, data);
  }

  archive(channelId) {
    return axios.post(`${this.url}/${channelId}/archive`);
  }

  unarchive(channelId) {
    return axios.post(`${this.url}/${channelId}/unarchive`);
  }

  getMembers(channelId) {
    return axios.get(`${this.url}/${channelId}/members`);
  }

  addMember(channelId, userId) {
    return axios.post(`${this.url}/${channelId}/members`, { user_id: userId });
  }

  removeMember(channelId, memberId) {
    return axios.delete(`${this.url}/${channelId}/members/${memberId}`);
  }

  updateMember(channelId, memberId, data) {
    return axios.patch(`${this.url}/${channelId}/members/${memberId}`, data);
  }

  toggleTypingStatus(channelId, typingStatus) {
    return axios.post(`${this.url}/${channelId}/toggle_typing_status`, {
      typing_status: typingStatus,
    });
  }

  markRead(channelId) {
    return axios.post(`${this.url}/${channelId}/mark_read`);
  }

  markUnread(channelId, messageId) {
    return axios.post(`${this.url}/${channelId}/mark_unread`, {
      message_id: messageId,
    });
  }
}

export default new InternalChatChannelsAPI();
