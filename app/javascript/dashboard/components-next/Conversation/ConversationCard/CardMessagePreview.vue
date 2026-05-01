<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { useMapGetter } from 'dashboard/composables/store';
import { MESSAGE_TYPE } from 'widget/helpers/constants';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  conversation: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const { getPlainText } = useMessageFormatter();
const currentUserId = useMapGetter('getCurrentUserID');

const isRemovedReaction = msg =>
  msg?.contentAttributes?.isReaction &&
  (msg?.contentAttributes?.deleted || !msg?.content);

// Cable updates mutate `lastNonActivityMessage` in place, so a freshly removed
// reaction can still be referenced here. Walk back through `messages` (which
// the backend filters via `hide_removed_reactions`) for the previous visible
// message instead of rendering "<sender> reagiu <>".
const previewMessage = computed(() => {
  const { lastNonActivityMessage, messages = [] } = props.conversation;
  // Pre-filter once so both fallbacks share the same removed-reaction guard.
  const nonRemovedMessages = messages.filter(m => !isRemovedReaction(m));
  // Mirrors conversationHelper.getLastMessage: when nothing else is available
  // a non-removed activity row is preferable to a blank "no content" preview.
  const lastMessageIncludingActivity =
    nonRemovedMessages[nonRemovedMessages.length - 1] || null;
  // The same row gets mutated in place when a reaction is toggled or echoed
  // from another device, so the snapshot may be stale. Resolve by id against
  // the live messages array first to pick up the freshest copy, then merge the
  // store fields onto the API snapshot so jbuilder-only fields like
  // `in_reply_to_snippet` survive the refresh (replacing would regress the
  // CHAT_LIST.REACTED_TO_SNIPPET preview to the generic fallback).
  const storeVersion = lastNonActivityMessage?.id
    ? messages.find(message => message.id === lastNonActivityMessage.id)
    : null;
  const refreshedCandidate = storeVersion
    ? { ...lastNonActivityMessage, ...storeVersion }
    : lastNonActivityMessage;
  if (refreshedCandidate && !isRemovedReaction(refreshedCandidate)) {
    return refreshedCandidate;
  }
  return (
    [...nonRemovedMessages].reverse().find(m => m?.messageType !== 2) ||
    lastMessageIncludingActivity
  );
});

const lastNonActivityMessageContent = computed(() => {
  const msg = previewMessage.value || {};
  const { customAttributes = {} } = props.conversation;
  const { email: { subject } = {} } = customAttributes;

  const isActiveReaction =
    msg?.contentAttributes?.isReaction &&
    !msg?.contentAttributes?.deleted &&
    !!msg?.content;
  if (isActiveReaction) {
    const senderId = msg.sender?.id;
    // Multi-device: agent reacts from the WhatsApp mobile app on the same
    // number as the inbox; the echo is outgoing without an agent. Treat it
    // as "you" so the preview doesn't show a blank reactor name.
    const isOwnInboxReaction =
      msg?.messageType === MESSAGE_TYPE.OUTGOING && !senderId;
    const senderName =
      senderId === currentUserId.value || isOwnInboxReaction
        ? t('CONVERSATION.REACTIONS.YOU')
        : msg.sender?.name || '';
    const params = {
      sender: senderName,
      emoji: msg.content,
      snippet: msg.inReplyToSnippet,
    };
    return params.snippet
      ? t('CHAT_LIST.REACTED_TO_SNIPPET', params)
      : t('CHAT_LIST.REACTED', params);
  }

  return getPlainText(subject || msg?.content || t('CHAT_LIST.NO_CONTENT'));
});

const assignee = computed(() => {
  const { meta: { assignee: agent = {} } = {} } = props.conversation;
  return {
    name: agent.name ?? agent.availableName,
    thumbnail: agent.thumbnail,
    status: agent.availabilityStatus,
  };
});

const unreadMessagesCount = computed(() => {
  const { unreadCount } = props.conversation;
  return unreadCount;
});
</script>

<template>
  <div class="flex items-end w-full gap-2 pb-1">
    <p class="w-full mb-0 text-sm leading-7 text-n-slate-12 line-clamp-2">
      {{ lastNonActivityMessageContent }}
    </p>
    <div class="flex items-center flex-shrink-0 gap-2 pb-2">
      <Avatar
        v-if="assignee.name"
        :name="assignee.name"
        :src="assignee.thumbnail"
        :size="20"
        :status="assignee.status"
        rounded-full
      />
      <div
        v-if="unreadMessagesCount > 0"
        class="inline-flex items-center justify-center rounded-full size-5 bg-n-brand"
      >
        <span class="text-xs font-semibold text-white">
          {{ unreadMessagesCount }}
        </span>
      </div>
    </div>
  </div>
</template>
