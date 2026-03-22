<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import MessageBubble from './MessageBubble.vue';
import MessageEditor from './MessageEditor.vue';

const props = defineProps({
  channelId: {
    type: Number,
    required: true,
  },
  parentMessage: {
    type: Object,
    required: true,
  },
  currentUserId: {
    type: Number,
    required: true,
  },
  isAdmin: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['close']);

const store = useStore();
const { t } = useI18n();

const isLoading = ref(false);
const isSending = ref(false);
const editingMessage = ref(null);
let activeThreadRequestId = null;

const threadReplies = computed(() => {
  return store.getters['internalChat/messages/getThreadReplies'](
    props.parentMessage.id
  );
});

const replyCount = computed(() => threadReplies.value.length);

async function fetchThread() {
  const requestId = props.parentMessage.id;
  activeThreadRequestId = requestId;
  isLoading.value = true;
  try {
    await store.dispatch('internalChat/messages/fetchThread', {
      channelId: props.channelId,
      messageId: props.parentMessage.id,
    });
  } catch {
    if (activeThreadRequestId !== requestId) return;
    useAlert(t('INTERNAL_CHAT.ERRORS.FETCH_MESSAGES'));
  } finally {
    if (activeThreadRequestId === requestId) {
      isLoading.value = false;
    }
  }
}

async function handleSendReply(content, options = {}) {
  isSending.value = true;
  try {
    if (editingMessage.value) {
      await store.dispatch('internalChat/messages/updateMessage', {
        channelId: props.channelId,
        messageId: editingMessage.value.id,
        data: { content },
      });
      editingMessage.value = null;
    } else {
      await store.dispatch('internalChat/messages/sendThreadReply', {
        channelId: props.channelId,
        parentMessageId: props.parentMessage.id,
        data: { content },
      });
      if (options.alsoSendInChannel) {
        await store.dispatch('internalChat/messages/sendMessage', {
          channelId: props.channelId,
          data: { content },
        });
      }
    }
  } catch {
    useAlert(t('INTERNAL_CHAT.ERRORS.SEND_MESSAGE'));
  } finally {
    isSending.value = false;
  }
}

function handleEditReply(message) {
  editingMessage.value = message;
}

function handleCancelEdit() {
  editingMessage.value = null;
}

function handleDeleteReply(message) {
  store
    .dispatch('internalChat/messages/deleteMessage', {
      channelId: props.channelId,
      messageId: message.id,
    })
    .catch(() => {
      useAlert(t('INTERNAL_CHAT.ERRORS.SEND_MESSAGE'));
    });
}

function handleAddReaction({ messageId, emoji }) {
  store
    .dispatch('internalChat/messages/addReaction', {
      channelId: props.channelId,
      messageId,
      emoji,
    })
    .catch(() => {
      // Silently ignore reaction errors
    });
}

function handleRemoveReaction({ messageId, reactionId }) {
  store
    .dispatch('internalChat/messages/removeReaction', {
      channelId: props.channelId,
      messageId,
      reactionId,
    })
    .catch(() => {
      // Silently ignore reaction errors
    });
}

function handleVote({ messageId, optionId }) {
  const msg = store.getters['internalChat/messages/getMessageById'](
    props.channelId,
    messageId
  );
  const pollId = msg?.poll?.id || msg?.content_attributes?.poll?.id;
  if (!pollId) return;
  store
    .dispatch('internalChat/polls/vote', {
      pollId,
      optionId,
      channelId: props.channelId,
    })
    .catch(() => {});
}

function handleUnvote({ messageId, optionId }) {
  const msg = store.getters['internalChat/messages/getMessageById'](
    props.channelId,
    messageId
  );
  const pollId = msg?.poll?.id || msg?.content_attributes?.poll?.id;
  if (!pollId) return;
  store
    .dispatch('internalChat/polls/unvote', {
      pollId,
      optionId,
      channelId: props.channelId,
    })
    .catch(() => {});
}

watch(
  () => props.parentMessage.id,
  () => fetchThread()
);

onMounted(() => {
  fetchThread();
});
</script>

<template>
  <div class="flex h-full w-96 flex-col border-l border-n-slate-5 bg-n-solid-1">
    <div
      class="flex items-center justify-between border-b border-n-slate-5 px-4 py-3"
    >
      <h3 class="text-sm font-semibold text-n-slate-12">
        {{ t('INTERNAL_CHAT.THREAD.TITLE') }}
      </h3>
      <button
        :aria-label="t('INTERNAL_CHAT.THREAD.CLOSE')"
        class="flex items-center justify-center rounded p-1 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        @click="emit('close')"
      >
        <Icon icon="i-lucide-x" class="size-4" />
      </button>
    </div>

    <div class="flex-1 overflow-y-auto">
      <div class="border-b border-n-slate-5 pb-2">
        <MessageBubble
          :message="parentMessage"
          :current-user-id="currentUserId"
          :is-admin="isAdmin"
          @edit="handleEditReply"
          @delete="handleDeleteReply"
          @add-reaction="handleAddReaction"
          @remove-reaction="handleRemoveReaction"
          @vote="handleVote"
          @unvote="handleUnvote"
        />
      </div>

      <div class="px-4 py-2">
        <span class="text-xs font-medium text-n-slate-10">
          {{ t('INTERNAL_CHAT.THREAD.REPLIES', { count: replyCount }) }}
        </span>
      </div>

      <div v-if="isLoading" class="flex items-center justify-center py-4">
        <Spinner :size="16" />
        <span class="ml-2 text-xs text-n-slate-10">
          {{ t('INTERNAL_CHAT.LOADING_MESSAGES') }}
        </span>
      </div>

      <div v-else>
        <MessageBubble
          v-for="reply in threadReplies"
          :key="reply.id"
          :message="reply"
          :current-user-id="currentUserId"
          :is-admin="isAdmin"
          @edit="handleEditReply"
          @delete="handleDeleteReply"
          @add-reaction="handleAddReaction"
          @remove-reaction="handleRemoveReaction"
          @vote="handleVote"
          @unvote="handleUnvote"
        />
      </div>
    </div>

    <MessageEditor
      :disabled="isSending"
      :editing-message="editingMessage"
      :placeholder="t('INTERNAL_CHAT.THREAD.REPLY_PLACEHOLDER')"
      :show-poll="false"
      show-also-send-in-channel
      @send="handleSendReply"
      @cancel-edit="handleCancelEdit"
    />
  </div>
</template>
