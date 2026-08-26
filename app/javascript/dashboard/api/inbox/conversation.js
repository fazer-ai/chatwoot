/* global axios */
import ApiClient from '../ApiClient';

class ConversationApi extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  get({
    inboxId,
    status,
    assigneeType,
    page,
    labels,
    teamId,
    conversationType,
    sortBy,
    updatedWithin,
    groupType,
  }) {
    return axios.get(this.url, {
      params: {
        inbox_id: inboxId,
        team_id: teamId,
        status,
        assignee_type: assigneeType,
        page,
        labels,
        conversation_type: conversationType,
        sort_by: sortBy,
        updated_within: updatedWithin,
        group_type: groupType,
      },
    });
  }

  filter(payload) {
    return axios.post(`${this.url}/filter`, payload.queryData, {
      params: {
        page: payload.page,
      },
    });
  }

  search({ q }) {
    return axios.get(`${this.url}/search`, {
      params: {
        q,
        page: 1,
      },
    });
  }

  toggleStatus({ conversationId, status, snoozedUntil = null }) {
    return axios.post(`${this.url}/${conversationId}/toggle_status`, {
      status,
      snoozed_until: snoozedUntil,
    });
  }

  // Asks the provider for the page before this thread's oldest message. Answers arrive on
  // the webhook minutes later, or never, so there is nothing useful in the response.
  syncHistory(conversationId) {
    return axios.post(`${this.url}/${conversationId}/sync_history`);
  }

  togglePriority({ conversationId, priority }) {
    return axios.post(`${this.url}/${conversationId}/toggle_priority`, {
      priority,
    });
  }

  assignAgent({ conversationId, agentId, assigneeType }) {
    return axios.post(`${this.url}/${conversationId}/assignments`, {
      assignee_id: agentId,
      assignee_type: assigneeType,
    });
  }

  assignTeam({ conversationId, teamId }) {
    const params = { team_id: teamId };
    return axios.post(`${this.url}/${conversationId}/assignments`, params);
  }

  markMessageRead({ id }) {
    return axios.post(`${this.url}/${id}/update_last_seen`);
  }

  markMessagesUnread({ id }) {
    return axios.post(`${this.url}/${id}/unread`);
  }

  toggleTyping({ conversationId, status, isPrivate }) {
    return axios.post(`${this.url}/${conversationId}/toggle_typing_status`, {
      typing_status: status,
      is_private: isPrivate,
    });
  }

  presenceSubscribe(conversationId) {
    return axios.post(`${this.url}/${conversationId}/presence_subscribe`);
  }

  presenceSubscribeBulk(conversationIds) {
    return axios.post(`${this.url}/presence_subscribe_bulk`, {
      conversation_ids: conversationIds,
    });
  }

  mute(conversationId) {
    return axios.post(`${this.url}/${conversationId}/mute`);
  }

  unmute(conversationId) {
    return axios.post(`${this.url}/${conversationId}/unmute`);
  }

  pin(conversationId) {
    return axios.post(`${this.url}/${conversationId}/pin`);
  }

  unpin(conversationId) {
    return axios.delete(`${this.url}/${conversationId}/unpin`);
  }

  fetchPins() {
    return axios.get(`${this.url}/pins`);
  }

  meta({
    inboxId,
    status,
    assigneeType,
    labels,
    teamId,
    conversationType,
    groupType,
  }) {
    return axios.get(`${this.url}/meta`, {
      params: {
        inbox_id: inboxId,
        status,
        assignee_type: assigneeType,
        labels,
        team_id: teamId,
        conversation_type: conversationType,
        group_type: groupType,
      },
    });
  }

  // Which of `conversationIds` are still in the tab, as a set: no page, no sort. Used to reconcile a
  // list that has grown longer than the tab's own count, which only happens when the store kept a
  // conversation that left the tab. Takes the same filters as `get` so both sides describe the same
  // tab, and asks only about the ids on screen so the answer can never outgrow the question.
  ids(
    {
      inboxId,
      status,
      assigneeType,
      labels,
      teamId,
      conversationType,
      groupType,
    },
    conversationIds
  ) {
    return axios.post(
      `${this.url}/ids`,
      { ids: conversationIds },
      {
        params: {
          inbox_id: inboxId,
          team_id: teamId,
          status,
          assignee_type: assigneeType,
          labels,
          conversation_type: conversationType,
          group_type: groupType,
        },
      }
    );
  }

  sendEmailTranscript({ conversationId, email }) {
    return axios.post(`${this.url}/${conversationId}/transcript`, { email });
  }

  updateCustomAttributes({ conversationId, customAttributes }) {
    return axios.post(`${this.url}/${conversationId}/custom_attributes`, {
      custom_attributes: customAttributes,
    });
  }

  fetchParticipants(conversationId) {
    return axios.get(`${this.url}/${conversationId}/participants`);
  }

  updateParticipants({ conversationId, userIds }) {
    return axios.patch(`${this.url}/${conversationId}/participants`, {
      user_ids: userIds,
    });
  }

  getAllAttachments(conversationId) {
    return axios.get(`${this.url}/${conversationId}/attachments`);
  }

  getInboxAssistant(conversationId) {
    return axios.get(`${this.url}/${conversationId}/inbox_assistant`);
  }

  delete(conversationId) {
    return axios.delete(`${this.url}/${conversationId}`);
  }
}

export default new ConversationApi();
