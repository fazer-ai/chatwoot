<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import InternalChatChannelsAPI from 'dashboard/api/internalChatChannels';
import ChannelHeader from './ChannelHeader.vue';
import MessageList from './MessageList.vue';
import MessageEditor from './MessageEditor.vue';
import TypingIndicator from './TypingIndicator.vue';
import ThreadPanel from './ThreadPanel.vue';
import PollCreator from './PollCreator.vue';

const props = defineProps({
  channelId: {
    type: Number,
    required: true,
  },
});

const store = useStore();
const { t } = useI18n();

const typingUsers = computed(() => {
  return (
    store.getters['internalChatTypingStatus/getUserList'](props.channelId) || []
  );
});
const editorRef = ref(null);
const activeThread = ref(null);
const showPollCreator = ref(false);

const currentUser = useMapGetter('getCurrentUser');

const channel = computed(() => {
  return store.getters['internalChat/getChannelById'](props.channelId);
});

const messages = computed(() => {
  return store.getters['internalChat/messages/getMessages'](props.channelId);
});

const messagesUIFlags = computed(() => {
  return store.getters['internalChat/messages/getUIFlags'];
});

const currentUserId = computed(() => {
  return currentUser.value?.id;
});

const isAdmin = computed(() => {
  const { role } = currentUser.value || {};
  return role === 'administrator';
});

const isArchived = computed(() => {
  return channel.value?.status === 'archived';
});

const pinnedMessage = computed(() => {
  return messages.value.find(m => m.content_attributes?.pinned) || null;
});

function markRead() {
  store.dispatch('internalChat/markRead', props.channelId);
}

async function fetchMessages() {
  try {
    await store.dispatch('internalChat/messages/fetchMessages', {
      channelId: props.channelId,
    });
  } catch {
    useAlert(t('INTERNAL_CHAT.ERRORS.FETCH_MESSAGES'));
  }
}

async function loadDraft() {
  try {
    await store.dispatch('internalChat/drafts/fetchDrafts');
    const draft = store.getters['internalChat/drafts/getDraftByChannelId'](
      props.channelId
    );
    if (editorRef.value) {
      editorRef.value.setContent(draft ? draft.content : '');
    }
  } catch {
    // Silently handle draft load error
  }
}

async function handleSend(content) {
  try {
    await store.dispatch('internalChat/messages/sendMessage', {
      channelId: props.channelId,
      data: { content },
    });
    markRead();
  } catch {
    useAlert(t('INTERNAL_CHAT.ERRORS.SEND_MESSAGE'));
  }
}

async function handleEdit(message) {
  try {
    await store.dispatch('internalChat/messages/updateMessage', {
      channelId: props.channelId,
      messageId: message.id,
      data: { content: message.content },
    });
  } catch {
    useAlert(t('INTERNAL_CHAT.ERRORS.SEND_MESSAGE'));
  }
}

async function handleDelete(message) {
  try {
    await store.dispatch('internalChat/messages/deleteMessage', {
      channelId: props.channelId,
      messageId: message.id,
    });
  } catch {
    useAlert(t('INTERNAL_CHAT.ERRORS.SEND_MESSAGE'));
  }
}

async function handleAddReaction({ messageId, emoji }) {
  try {
    await store.dispatch('internalChat/messages/addReaction', {
      channelId: props.channelId,
      messageId,
      emoji,
    });
  } catch {
    // Silently ignore reaction errors
  }
}

async function handleRemoveReaction({ messageId, reactionId }) {
  try {
    await store.dispatch('internalChat/messages/removeReaction', {
      channelId: props.channelId,
      messageId,
      reactionId,
    });
  } catch {
    // Silently ignore reaction errors
  }
}

async function handleLoadMore() {
  if (!messages.value.length) return;
  const oldestMessage = messages.value[0];
  try {
    await store.dispatch('internalChat/messages/fetchMessages', {
      channelId: props.channelId,
      params: { before: oldestMessage.created_at },
    });
  } catch {
    // silently ignore pagination errors
  }
}

function handleTyping() {
  InternalChatChannelsAPI.toggleTypingStatus(props.channelId, 'on');
}

function handleReply(message) {
  activeThread.value = message;
}

function handleOpenThread(message) {
  activeThread.value = message;
}

function closeThread() {
  activeThread.value = null;
}

async function handlePin(message) {
  try {
    await store.dispatch('internalChat/messages/pinMessage', {
      channelId: props.channelId,
      messageId: message.id,
    });
  } catch {
    useAlert(t('INTERNAL_CHAT.ERRORS.SEND_MESSAGE'));
  }
}

async function handleUnpin(message) {
  try {
    await store.dispatch('internalChat/messages/unpinMessage', {
      channelId: props.channelId,
      messageId: message.id,
    });
  } catch {
    useAlert(t('INTERNAL_CHAT.ERRORS.SEND_MESSAGE'));
  }
}

async function handleVote({ messageId, optionId }) {
  const msg = store.getters['internalChat/messages/getMessageById'](
    props.channelId,
    messageId
  );
  const pollId = msg?.poll?.id || msg?.content_attributes?.poll?.id;
  if (!pollId) return;
  try {
    await store.dispatch('internalChat/polls/vote', { pollId, optionId });
  } catch {
    useAlert(t('INTERNAL_CHAT.ERRORS.SEND_MESSAGE'));
  }
}

async function handleUnvote({ messageId }) {
  const msg = store.getters['internalChat/messages/getMessageById'](
    props.channelId,
    messageId
  );
  const pollId = msg?.poll?.id || msg?.content_attributes?.poll?.id;
  if (!pollId) return;
  try {
    await store.dispatch('internalChat/polls/unvote', { pollId });
  } catch {
    useAlert(t('INTERNAL_CHAT.ERRORS.SEND_MESSAGE'));
  }
}

async function handlePollSubmit(pollData) {
  try {
    await store.dispatch('internalChat/polls/createPoll', {
      channelId: props.channelId,
      data: pollData,
    });
    showPollCreator.value = false;
  } catch {
    useAlert(t('INTERNAL_CHAT.ERRORS.SEND_MESSAGE'));
  }
}

async function handleDraftUpdate(content) {
  if (!content || !content.trim()) return;
  try {
    await store.dispatch('internalChat/drafts/saveDraft', {
      channelId: props.channelId,
      content,
    });
  } catch {
    // Silently handle draft save error
  }
}

watch(
  () => props.channelId,
  () => {
    fetchMessages();
    markRead();
    loadDraft();
    activeThread.value = null;
  }
);

onMounted(() => {
  fetchMessages();
  markRead();
  loadDraft();
});
</script>

<template>
  <div class="flex h-full">
    <div class="flex flex-1 flex-col bg-n-solid-1 min-w-0">
      <ChannelHeader
        :channel="channel"
        :pinned-message="pinnedMessage"
        @settings="() => {}"
      />
      <MessageList
        :messages="messages"
        :current-user-id="currentUserId"
        :is-admin="isAdmin"
        :is-loading="messagesUIFlags.isFetching"
        @edit="handleEdit"
        @delete="handleDelete"
        @reply="handleReply"
        @open-thread="handleOpenThread"
        @add-reaction="handleAddReaction"
        @remove-reaction="handleRemoveReaction"
        @pin="handlePin"
        @unpin="handleUnpin"
        @vote="handleVote"
        @unvote="handleUnvote"
        @load-more="handleLoadMore"
      />
      <TypingIndicator :typing-users="typingUsers" />
      <MessageEditor
        v-if="!isArchived"
        ref="editorRef"
        :disabled="messagesUIFlags.isSending"
        @send="handleSend"
        @typing="handleTyping"
        @draft-update="handleDraftUpdate"
        @create-poll="showPollCreator = true"
      />
      <div
        v-else
        class="border-t border-n-slate-5 bg-n-solid-2 px-4 py-3 text-center text-sm text-n-slate-10"
      >
        {{ t('INTERNAL_CHAT.CHANNEL.ARCHIVED') }}
      </div>
    </div>

    <ThreadPanel
      v-if="activeThread"
      :channel-id="channelId"
      :parent-message="activeThread"
      :current-user-id="currentUserId"
      :is-admin="isAdmin"
      @close="closeThread"
    />

    <PollCreator
      v-if="showPollCreator"
      @submit="handlePollSubmit"
      @close="showPollCreator = false"
    />
  </div>
</template>
