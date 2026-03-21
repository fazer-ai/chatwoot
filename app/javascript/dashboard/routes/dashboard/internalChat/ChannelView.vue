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

const props = defineProps({
  channelId: {
    type: Number,
    required: true,
  },
});

const store = useStore();
const { t } = useI18n();

const typingUsers = ref([]);
const editorRef = ref(null);

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
  return channel.value?.archived;
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
  // TODO: replace with modal dialog
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

function handleTyping() {
  InternalChatChannelsAPI.toggleTypingStatus(props.channelId, 'on');
}

watch(
  () => props.channelId,
  () => {
    fetchMessages();
    markRead();
  }
);

onMounted(() => {
  fetchMessages();
  markRead();
});
</script>

<template>
  <div class="flex h-full flex-col bg-n-solid-1">
    <ChannelHeader :channel="channel" />
    <MessageList
      :messages="messages"
      :current-user-id="currentUserId"
      :is-admin="isAdmin"
      :is-loading="messagesUIFlags.isFetching"
      @edit="handleEdit"
      @delete="handleDelete"
      @add-reaction="handleAddReaction"
      @remove-reaction="handleRemoveReaction"
    />
    <TypingIndicator :typing-users="typingUsers" />
    <MessageEditor
      v-if="!isArchived"
      ref="editorRef"
      :disabled="messagesUIFlags.isSending"
      @send="handleSend"
      @typing="handleTyping"
    />
    <div
      v-else
      class="border-t border-n-slate-5 bg-n-solid-2 px-4 py-3 text-center text-sm text-n-slate-10"
    >
      {{ t('INTERNAL_CHAT.CHANNEL.ARCHIVED') }}
    </div>
  </div>
</template>
