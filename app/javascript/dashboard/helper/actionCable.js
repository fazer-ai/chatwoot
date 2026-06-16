import AuthAPI from '../api/auth';
import BaseActionCableConnector from '../../shared/helpers/BaseActionCableConnector';
import DashboardAudioNotificationHelper from './AudioAlerts/DashboardAudioNotificationHelper';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import { useImpersonation } from 'dashboard/composables/useImpersonation';
import { pendingGroupNavigation } from 'dashboard/helper/pendingGroupNavigation';
import { useCallsStore } from 'dashboard/stores/calls';
import {
  applyOutboundAnswer,
  armOutboundRecorder,
  handleWhatsappRemoteEnd,
  isLocalWhatsappCall,
} from 'dashboard/composables/useWhatsappCallSession';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const { isImpersonating } = useImpersonation();
const UNREAD_COUNTS_REFETCH_THROTTLE_MS = 5000;

class ActionCableConnector extends BaseActionCableConnector {
  constructor(app, pubsubToken) {
    const { websocketURL = '' } = window.chatwootConfig || {};
    super(app, pubsubToken, websocketURL);
    this.CancelTyping = [];
    this.lastUnreadCountsFetchAt = null;
    this.unreadCountsFetchTimer = null;
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
      'conversation.recording': this.onRecording,
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
      'conversation.unread_count_changed':
        this.onConversationUnreadCountChanged,
      'account.cache_invalidated': this.onCacheInvalidate,
      'inbox.provider_connection_updated':
        this.onInboxProviderConnectionUpdated,
      'account.enrichment_completed': this.onEnrichmentCompleted,
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
      'voice_call.incoming': this.onVoiceCallIncoming,
      'voice_call.outbound_connected': this.onVoiceCallOutboundConnected,
      'voice_call.outbound_accepted': this.onVoiceCallOutboundAccepted,
      'voice_call.ended': this.onVoiceCallEnded,
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

  onConversationUnreadCountChanged = () => {
    this.throttledFetchConversationUnreadCounts();
  };

  throttledFetchConversationUnreadCounts = () => {
    const now = Date.now();
    const elapsedTime = now - this.lastUnreadCountsFetchAt;

    if (
      this.lastUnreadCountsFetchAt === null ||
      elapsedTime >= UNREAD_COUNTS_REFETCH_THROTTLE_MS
    ) {
      this.clearUnreadCountsFetchTimer();
      this.fetchConversationUnreadCounts();
      return;
    }

    if (this.unreadCountsFetchTimer) return;

    this.unreadCountsFetchTimer = setTimeout(() => {
      this.unreadCountsFetchTimer = null;
      this.fetchConversationUnreadCounts();
    }, UNREAD_COUNTS_REFETCH_THROTTLE_MS - elapsedTime);
  };

  clearUnreadCountsFetchTimer = () => {
    if (!this.unreadCountsFetchTimer) return;

    clearTimeout(this.unreadCountsFetchTimer);
    this.unreadCountsFetchTimer = null;
  };

  fetchConversationUnreadCounts = () => {
    if (!this.isConversationUnreadCountsEnabled()) return;

    this.lastUnreadCountsFetchAt = Date.now();
    this.app.$store.dispatch('conversationUnreadCounts/get');
  };

  isConversationUnreadCountsEnabled = () => {
    const accountId = this.app.$store.getters.getCurrentAccountId;
    const isFeatureEnabled =
      this.app.$store.getters['accounts/isFeatureEnabledonAccount'];

    return isFeatureEnabled?.(
      accountId,
      FEATURE_FLAGS.CONVERSATION_UNREAD_COUNTS
    );
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
    const timerKey = `${conversation.id}:${user.type}:${user.id}`;

    this.clearTimer(timerKey);
    this.app.$store.dispatch('conversationTypingStatus/create', {
      conversationId: conversation.id,
      user: { ...user, recording: false },
    });
    this.initTimer({ conversation, user, timerKey });
  };

  onRecording = ({ conversation, user }) => {
    const timerKey = `${conversation.id}:${user.type}:${user.id}`;

    this.clearTimer(timerKey);
    this.app.$store.dispatch('conversationTypingStatus/create', {
      conversationId: conversation.id,
      user: { ...user, recording: true },
    });
    this.initTimer({ conversation, user, timerKey });
  };

  onTypingOff = ({ conversation, user }) => {
    const timerKey = `${conversation.id}:${user.type}:${user.id}`;

    this.clearTimer(timerKey);
    this.app.$store.dispatch('conversationTypingStatus/destroy', {
      conversationId: conversation.id,
      user,
    });
  };

  onConversationMentioned = data => {
    this.app.$store.dispatch('addMentions', data);
  };

  clearTimer = timerKey => {
    const timerEvent = this.CancelTyping[timerKey];

    if (timerEvent) {
      clearTimeout(timerEvent);
      this.CancelTyping[timerKey] = null;
    }
  };

  initTimer = ({ conversation, user, timerKey }) => {
    // Turn off typing automatically after 30 seconds
    this.CancelTyping[timerKey] = setTimeout(() => {
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

  onEnrichmentCompleted = () => {
    this.app.$store.dispatch('accounts/get', { silent: true });
  };

  onCacheInvalidate = data => {
    const keys = data.cache_keys;
    this.app.$store.dispatch('labels/revalidate', { newKey: keys.label });
    this.app.$store.dispatch('inboxes/revalidate', { newKey: keys.inbox });
    this.app.$store.dispatch('teams/revalidate', { newKey: keys.team });
  };

  onInboxProviderConnectionUpdated = data => {
    this.app.$store.dispatch('inboxes/updateProviderConnection', {
      id: data.inbox_id,
      providerConnection: data.provider_connection,
    });
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
      channelId: data.internal_chat_channel_id,
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

  onVoiceCallIncoming = data => {
    if (data?.provider !== VOICE_CALL_PROVIDERS.WHATSAPP) return;
    // Defense in depth: the server already filters to online agent streams,
    // but if anything ever broadcasts to a broader stream (e.g. account-wide),
    // an agent who's set availability=offline/busy shouldn't ring.
    const availability = this.app.$store.getters.getCurrentUserAvailability;
    if (availability !== 'online') return;

    useCallsStore().addCall({
      callSid: data.call_id,
      callId: data.id,
      conversationId: data.conversation_id,
      inboxId: data.inbox_id,
      callDirection: VOICE_CALL_DIRECTION.INBOUND,
      provider: VOICE_CALL_PROVIDERS.WHATSAPP,
      sdpOffer: data.sdp_offer,
      iceServers: data.ice_servers,
      caller: data.caller,
    });
  };

  // `connect` is the WebRTC tunnel-ready signal (fires ~20s before pickup
  // for outbound). Apply the SDP answer so the handshake completes during
  // ringing, but stay non-active until `outbound_accepted` arrives.
  // eslint-disable-next-line class-methods-use-this
  onVoiceCallOutboundConnected = async data => {
    if (data?.provider !== VOICE_CALL_PROVIDERS.WHATSAPP || !data.sdp_answer)
      return;
    // Account-wide broadcast that can arrive before /initiate sets this tab's
    // call id. applyOutboundAnswer filters foreign calls and buffers the answer
    // until the id is known, so we must not drop it here on a null activeCallId.
    try {
      await applyOutboundAnswer(data.id, data.sdp_answer);
    } catch (_) {
      /* noop */
    }
  };

  // Real pickup signal — Meta sends status=ACCEPTED on the call when the
  // contact answers. Flip active (timer starts) and arm the recorder.
  // eslint-disable-next-line class-methods-use-this
  onVoiceCallOutboundAccepted = data => {
    if (data?.provider !== VOICE_CALL_PROVIDERS.WHATSAPP) return;
    const store = useCallsStore();
    if (!store.calls.some(c => c.callSid === data.call_id)) return;
    store.setCallActive(data.call_id);
    armOutboundRecorder();
  };

  // eslint-disable-next-line class-methods-use-this
  onVoiceCallEnded = async data => {
    if (data?.provider !== VOICE_CALL_PROVIDERS.WHATSAPP) return;
    // The store entry should always be removed for this account-wide broadcast,
    // but the WebRTC/recorder teardown must only run for the call this tab owns
    // — otherwise an unrelated agent's call ending would stop this tab's
    // recorder and upload its chunks against the wrong call id.
    if (isLocalWhatsappCall(data.id)) {
      // Await upload before removeCall — the store's sync teardown would otherwise
      // wipe the recorder chunks before they reach the server.
      try {
        await handleWhatsappRemoteEnd(data.id);
      } catch (_) {
        /* noop */
      }
    }
    useCallsStore().removeCall(data.call_id);
  };
}

export default {
  init(store, pubsubToken) {
    return new ActionCableConnector({ $store: store }, pubsubToken);
  },
};
