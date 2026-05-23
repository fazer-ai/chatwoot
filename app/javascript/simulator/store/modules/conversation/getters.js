import { MESSAGE_TYPE } from 'simulator/helpers/constants';
import { groupBy } from 'simulator/helpers/utils';
import { groupConversationBySender } from './helpers';
import { formatUnixDate } from 'shared/helpers/DateHelper';

// A reaction message is stored as a regular Message row with
// `content_attributes.is_reaction: true`. We strip these from the
// scrollable message feed and instead surface them as a chip on the
// target bubble (see `getReactionsByMessageId`).
const isReactionMessage = message => !!message?.content_attributes?.is_reaction;

const isActiveReaction = message =>
  isReactionMessage(message) &&
  message.content &&
  !message.content_attributes?.deleted;

export const getters = {
  getAllMessagesLoaded: _state => _state.uiFlags.allMessagesLoaded,
  getIsCreating: _state => _state.uiFlags.isCreating,
  getIsAgentTyping: _state => _state.uiFlags.isAgentTyping,
  getConversation: _state => _state.conversations,
  getConversationSize: _state => Object.keys(_state.conversations).length,
  getEarliestMessage: _state => {
    const conversation = Object.values(_state.conversations);
    if (conversation.length) {
      return conversation[0];
    }
    return {};
  },
  getLastMessage: _state => {
    const conversation = Object.values(_state.conversations);
    if (conversation.length) {
      return conversation[conversation.length - 1];
    }
    return {};
  },
  getGroupedConversation: _state => {
    const messagesForFeed = Object.values(_state.conversations).filter(
      message => !isReactionMessage(message)
    );
    const conversationGroupedByDate = groupBy(messagesForFeed, message =>
      formatUnixDate(message.created_at)
    );
    return Object.keys(conversationGroupedByDate).map(date => ({
      date,
      messages: groupConversationBySender(conversationGroupedByDate[date]),
    }));
  },
  // Returns a map keyed by target_message_id with the latest active
  // reaction from each side ("contact" = simulator user, "agent" =
  // dashboard user replying from AurisChat). Used by the bubble
  // components to render a small chip below the message.
  getReactionsByMessageId: _state => {
    const map = {};
    Object.values(_state.conversations).forEach(message => {
      if (!isActiveReaction(message)) return;
      const targetId = message.content_attributes?.in_reply_to;
      if (!targetId) return;
      if (!map[targetId]) map[targetId] = {};
      const side =
        message.message_type === MESSAGE_TYPE.INCOMING ? 'contact' : 'agent';
      map[targetId][side] = {
        id: message.id,
        emoji: message.content,
      };
    });
    return map;
  },
  getPendingCustomAttributes: _state => _state.pendingCustomAttributes,
  getPendingLabels: _state => _state.pendingLabels,
  getIsFetchingList: _state => _state.uiFlags.isFetchingList,
  getMessageCount: _state => {
    return Object.values(_state.conversations).length;
  },
  getUnreadMessageCount: _state => {
    const { userLastSeenAt } = _state.meta;
    return Object.values(_state.conversations).filter(chat => {
      const { created_at: createdAt, message_type: messageType } = chat;
      const isOutGoing = messageType === MESSAGE_TYPE.OUTGOING;
      const hasNotSeen = userLastSeenAt
        ? createdAt * 1000 > userLastSeenAt * 1000
        : true;
      return hasNotSeen && isOutGoing;
    }).length;
  },
  getUnreadTextMessages: (_state, _getters) => {
    const unreadCount = _getters.getUnreadMessageCount;
    const allMessages = [...Object.values(_state.conversations)];
    const unreadAgentMessages = allMessages.filter(message => {
      const { message_type: messageType } = message;
      return messageType === MESSAGE_TYPE.OUTGOING;
    });
    const maxUnreadCount = Math.min(unreadCount, 3);
    return unreadAgentMessages.splice(-maxUnreadCount);
  },
};
