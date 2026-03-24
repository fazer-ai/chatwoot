import AuthAPI from '../api/auth';
import BaseActionCableConnector from '../../shared/helpers/BaseActionCableConnector';
import DashboardAudioNotificationHelper from './AudioAlerts/DashboardAudioNotificationHelper';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import { useImpersonation } from 'dashboard/composables/useImpersonation';
import { pendingGroupNavigation } from 'dashboard/helper/pendingGroupNavigation';

const { isImpersonating } = useImpersonation();

class ActionCableConnector extends BaseActionCableConnector {
  constructor(app, pubsubToken) {
    const { websocketURL = '' } = window.chatwootConfig || {};
    super(app, pubsubToken, websocketURL);
    this.CancelTyping = [];
    this.events = {
      'message.created': this.onMessageCreated,
      'message.updated': this.onMessageUpdated,
      'conversation.created': this.onConversationCreated,
      'conversation.status_changed': this.onStatusChange,
      'user:logout': this.onLogout,
      'page:reload': this.onReload,
      'assignee.changed': this.onAssigneeChanged,
      'conversation.typing_on': this.onTypingOn,
      'conversation.typing_off': this.onTypingOff,
      'conversation.contact_changed': this.onConversationContactChange,
      'presence.update': this.onPresenceUpdate,
      'contact.deleted': this.onContactDelete,
      'contact.updated': this.onContactUpdate,
      'contact.group_synced': this.onContactGroupSynced,
      'conversation.mentioned': this.onConversationMentioned,
      'notification.created': this.onNotificationCreated,
      'notification.deleted': this.onNotificationDeleted,
      'notification.updated': this.onNotificationUpdated,
      'conversation.read': this.onConversationRead,
      'conversation.updated': this.onConversationUpdated,
      'account.cache_invalidated': this.onCacheInvalidate,
      'copilot.message.created': this.onCopilotMessageCreated,
      'scheduled_message.created': this.onScheduledMessageCreated,
      'scheduled_message.updated': this.onScheduledMessageUpdated,
      'scheduled_message.deleted': this.onScheduledMessageDeleted,
      'recurring_scheduled_message.created':
        this.onRecurringScheduledMessageCreated,
      'recurring_scheduled_message.updated':
        this.onRecurringScheduledMessageUpdated,
      'recurring_scheduled_message.deleted':
        this.onRecurringScheduledMessageDeleted,
      'internal_chat.channel.updated': this.onInternalChatChannelUpdated,
      'internal_chat.message.created': this.onInternalChatMessageCreated,
      'internal_chat.message.updated': this.onInternalChatMessageUpdated,
      'internal_chat.message.deleted': this.onInternalChatMessageDeleted,
      'internal_chat.typing_on': this.onInternalChatTypingOn,
      'internal_chat.typing_off': this.onInternalChatTypingOff,
      'internal_chat.reaction.created': this.onInternalChatReactionCreated,
      'internal_chat.reaction.deleted': this.onInternalChatReactionDeleted,
      'internal_chat.poll.voted': this.onInternalChatPollVoted,
    };
  }

  // eslint-disable-next-line class-methods-use-this
  onReconnect = () => {
    emitter.emit(BUS_EVENTS.WEBSOCKET_RECONNECT);
  };

  // eslint-disable-next-line class-methods-use-this
  onDisconnected = () => {
    emitter.emit(BUS_EVENTS.WEBSOCKET_DISCONNECT);
  };

  isAValidEvent = data => {
    return this.app.$store.getters.getCurrentAccountId === data.account_id;
  };

  onMessageUpdated = data => {
    this.app.$store.dispatch('updateMessage', data);
  };

  onPresenceUpdate = data => {
    if (isImpersonating.value) return;
    this.app.$store.dispatch('contacts/updatePresence', data.contacts);
    this.app.$store.dispatch('agents/updatePresence', data.users);
    this.app.$store.dispatch('setCurrentUserAvailability', data.users);
  };

  onConversationContactChange = payload => {
    const { meta = {}, id: conversationId } = payload;
    const { sender } = meta || {};
    if (conversationId) {
      this.app.$store.dispatch('updateConversationContact', {
        conversationId,
        ...sender,
      });
    }
  };

  onAssigneeChanged = payload => {
    const { id } = payload;
    if (id) {
      this.app.$store.dispatch('updateConversation', payload);
    }
    this.fetchConversationStats();
  };

  onConversationCreated = data => {
    this.app.$store.dispatch('addConversation', data);
    this.fetchConversationStats();

    const pendingJid = pendingGroupNavigation.consume();
    if (pendingJid && data.meta?.sender?.identifier === pendingJid) {
      emitter.emit(BUS_EVENTS.NAVIGATE_TO_GROUP, { conversationId: data.id });
    } else if (pendingJid) {
      pendingGroupNavigation.set(pendingJid);
    }
  };

  onConversationRead = data => {
    this.app.$store.dispatch('updateConversation', data);
  };

  // eslint-disable-next-line class-methods-use-this
  onLogout = () => AuthAPI.logout();

  onMessageCreated = data => {
    const {
      conversation: { last_activity_at: lastActivityAt },
      conversation_id: conversationId,
    } = data;
    DashboardAudioNotificationHelper.onNewMessage(data);
    this.app.$store.dispatch('addMessage', data);
    this.app.$store.dispatch('updateConversationLastActivity', {
      lastActivityAt,
      conversationId,
    });
  };

  // eslint-disable-next-line class-methods-use-this
  onReload = () => window.location.reload();

  onStatusChange = data => {
    this.app.$store.dispatch('updateConversation', data);
    this.fetchConversationStats();
  };

  onConversationUpdated = data => {
    this.app.$store.dispatch('updateConversation', data);
    this.fetchConversationStats();
  };

  onScheduledMessageCreated = data => {
    this.app.$store.dispatch('handleScheduledMessageCreated', data);
  };

  onScheduledMessageUpdated = data => {
    this.app.$store.dispatch('handleScheduledMessageUpdated', data);
  };

  onScheduledMessageDeleted = data => {
    this.app.$store.dispatch('handleScheduledMessageDeleted', data);
  };

  onRecurringScheduledMessageCreated = data => {
    this.app.$store.dispatch('handleRecurringScheduledMessageCreated', data);
  };

  onRecurringScheduledMessageUpdated = data => {
    this.app.$store.dispatch('handleRecurringScheduledMessageUpdated', data);
  };

  onRecurringScheduledMessageDeleted = data => {
    this.app.$store.dispatch('handleRecurringScheduledMessageDeleted', data);
  };

  onTypingOn = ({ conversation, user }) => {
    const conversationId = conversation.id;

    this.clearTimer(conversationId);
    this.app.$store.dispatch('conversationTypingStatus/create', {
      conversationId,
      user,
    });
    this.initTimer({ conversation, user });
  };

  onTypingOff = ({ conversation, user }) => {
    const conversationId = conversation.id;

    this.clearTimer(conversationId);
    this.app.$store.dispatch('conversationTypingStatus/destroy', {
      conversationId,
      user,
    });
  };

  onConversationMentioned = data => {
    this.app.$store.dispatch('addMentions', data);
  };

  clearTimer = conversationId => {
    const timerEvent = this.CancelTyping[conversationId];

    if (timerEvent) {
      clearTimeout(timerEvent);
      this.CancelTyping[conversationId] = null;
    }
  };

  initTimer = ({ conversation, user }) => {
    const conversationId = conversation.id;
    // Turn off typing automatically after 30 seconds
    this.CancelTyping[conversationId] = setTimeout(() => {
      this.onTypingOff({ conversation, user });
    }, 30000);
  };

  // eslint-disable-next-line class-methods-use-this
  fetchConversationStats = () => {
    emitter.emit('fetch_conversation_stats');
  };

  onContactDelete = data => {
    this.app.$store.dispatch(
      'contacts/deleteContactThroughConversations',
      data.id
    );
    this.fetchConversationStats();
  };

  onContactUpdate = data => {
    this.app.$store.dispatch('contacts/updateContact', data);
  };

  onContactGroupSynced = data => {
    this.app.$store.dispatch('groupMembers/setGroupMembers', {
      contactId: data.id,
      members: data.group_members,
      inboxPhoneNumber: data.inbox_phone_number,
      isInboxAdmin: data.is_inbox_admin,
    });
    this.app.$store.dispatch('contacts/updateContact', data);
  };

  onNotificationCreated = data => {
    this.app.$store.dispatch('notifications/addNotification', data);
  };

  onNotificationDeleted = data => {
    this.app.$store.dispatch('notifications/deleteNotification', data);
  };

  onNotificationUpdated = data => {
    this.app.$store.dispatch('notifications/updateNotification', data);
  };

  onCopilotMessageCreated = data => {
    this.app.$store.dispatch('copilotMessages/upsert', data);
  };

  onCacheInvalidate = data => {
    const keys = data.cache_keys;
    this.app.$store.dispatch('labels/revalidate', { newKey: keys.label });
    this.app.$store.dispatch('inboxes/revalidate', { newKey: keys.inbox });
    this.app.$store.dispatch('teams/revalidate', { newKey: keys.team });
  };

  onInternalChatMessageCreated = data => {
    this.app.$store.dispatch('internalChat/messages/addMessageFromCable', {
      channelId: data.internal_chat_channel_id,
      message: data,
    });
    const channel = this.app.$store.getters['internalChat/getChannelById'](
      data.internal_chat_channel_id
    );
    if (channel) {
      const currentUserId = this.app.$store.getters.getCurrentUser?.id;
      const isOwnMessage = data.sender?.id === currentUserId;
      const activeChannelId =
        this.app.$store.getters['internalChat/getActiveChannelId'];
      const isActiveChannel = activeChannelId === data.internal_chat_channel_id;
      const mentionedIds = data.content_attributes?.mentioned_user_ids || [];
      const isMentioned = mentionedIds.includes(currentUserId);
      this.app.$store.dispatch('internalChat/updateChannel', {
        id: data.internal_chat_channel_id,
        unread_count:
          isActiveChannel || isOwnMessage
            ? channel.unread_count || 0
            : (channel.unread_count || 0) + 1,
        has_unread_mention:
          isActiveChannel || isOwnMessage
            ? false
            : channel.has_unread_mention || isMentioned,
        last_activity_at: data.created_at,
      });
    }
  };

  onInternalChatMessageUpdated = data => {
    this.app.$store.dispatch('internalChat/messages/updateMessageFromCable', {
      channelId: data.internal_chat_channel_id,
      message: data,
    });
  };

  onInternalChatMessageDeleted = data => {
    this.app.$store.dispatch('internalChat/messages/deleteMessageFromCable', {
      channelId: data.internal_chat_channel_id,
      messageId: data.id,
    });
  };

  onInternalChatTypingOn = ({ channel, user }) => {
    this.app.$store.dispatch('internalChatTypingStatus/create', {
      channelId: channel.id,
      user,
    });
  };

  onInternalChatTypingOff = ({ channel, user }) => {
    this.app.$store.dispatch('internalChatTypingStatus/destroy', {
      channelId: channel.id,
      user,
    });
  };

  onInternalChatReactionCreated = data => {
    this.app.$store.dispatch('internalChat/messages/addReactionFromCable', {
      channelId: data.internal_chat_channel_id,
      messageId: data.message_id,
      reaction: data,
    });
  };

  onInternalChatReactionDeleted = data => {
    this.app.$store.dispatch('internalChat/messages/removeReactionFromCable', {
      channelId: data.internal_chat_channel_id || data.channel_id,
      messageId: data.message_id,
      reactionId: data.id,
    });
  };

  onInternalChatChannelUpdated = data => {
    const currentUserId = this.app.$store.getters.getCurrentUser?.id;
    const memberIds = data.member_user_ids;

    if (memberIds && currentUserId && data.channel_type === 'private_channel') {
      if (!memberIds.includes(currentUserId)) {
        // Current user was removed from channel
        this.app.$store.commit('internalChat/DELETE_CHANNEL', data.id);
        return;
      }
      // Current user was added: if channel not in store, refetch channels
      const existing = this.app.$store.getters['internalChat/getChannelById'](
        data.id
      );
      if (!existing) {
        this.app.$store.dispatch('internalChat/get');
        return;
      }
    }

    this.app.$store.dispatch('internalChat/updateChannel', data);
  };

  onInternalChatPollVoted = data => {
    this.app.$store.dispatch('internalChat/polls/updatePollFromCable', {
      channelId: data.internal_chat_channel_id,
      poll: data,
    });
  };
}

export default {
  init(store, pubsubToken) {
    return new ActionCableConnector({ $store: store }, pubsubToken);
  },
};
