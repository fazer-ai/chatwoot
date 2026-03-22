<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import MessageFormatter from 'shared/helpers/MessageFormatter';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useAlert } from 'dashboard/composables';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ReactionDisplay from './ReactionDisplay.vue';
import EmojiReactionPicker from './EmojiReactionPicker.vue';
import PollDisplay from './PollDisplay.vue';

const props = defineProps({
  message: {
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

const emit = defineEmits([
  'edit',
  'delete',
  'reply',
  'openThread',
  'addReaction',
  'removeReaction',
  'pin',
  'unpin',
  'vote',
  'unvote',
]);

const { t } = useI18n();

const senderName = computed(() => {
  return props.message.sender?.name || '';
});

const senderAvatar = computed(() => {
  return props.message.sender?.avatar_url || '';
});

const timestamp = computed(() => {
  const createdAt = props.message.created_at;
  if (!createdAt) return '';
  const unixTime =
    typeof createdAt === 'number'
      ? createdAt
      : Math.floor(new Date(createdAt).getTime() / 1000);
  return messageTimestamp(unixTime, 'h:mm a');
});

const isOwnMessage = computed(() => {
  return props.message.sender?.id === props.currentUserId;
});

const isEdited = computed(() => {
  return !!props.message.content_attributes?.edited_at;
});

const isDeleted = computed(() => {
  return !!props.message.content_attributes?.deleted;
});

const isPoll = computed(() => {
  return props.message.content_type === 'poll';
});

const isPinned = computed(() => {
  return !!props.message.content_attributes?.pinned;
});

const threadReplyCount = computed(() => {
  return props.message.replies_count || 0;
});

const canEdit = computed(() => {
  return isOwnMessage.value && !isDeleted.value && !isPoll.value;
});

const canDelete = computed(() => {
  return (isOwnMessage.value || props.isAdmin) && !isDeleted.value;
});

const canPin = computed(() => {
  return (
    (isOwnMessage.value || props.isAdmin) &&
    !isDeleted.value &&
    !props.message.parent_id
  );
});

const messageContent = computed(() => {
  if (isDeleted.value) {
    return t('INTERNAL_CHAT.MESSAGE.DELETED');
  }
  return props.message.content || '';
});

const renderedContent = computed(() => {
  if (isDeleted.value) return '';
  const formatter = new MessageFormatter(props.message.content || '');
  return formatter.formattedMessage;
});

const reactions = computed(() => {
  return props.message.reactions || [];
});

const attachments = computed(() => {
  if (isDeleted.value) return [];
  return props.message.attachments || [];
});

const deleteDialogRef = ref(null);

function handleEdit() {
  emit('edit', props.message);
}

function handleDelete() {
  deleteDialogRef.value?.open();
}

function confirmDelete() {
  emit('delete', props.message);
  deleteDialogRef.value?.close();
}

function handleReply() {
  emit('reply', props.message);
}

function handleOpenThread() {
  emit('openThread', props.message);
}

function handlePin() {
  if (isPinned.value) {
    emit('unpin', props.message);
  } else {
    emit('pin', props.message);
  }
}

function handleCopyLink() {
  const baseUrl = window.chatwootConfig?.hostURL || window.location.origin;
  const path = window.location.pathname;
  const url = `${baseUrl}${path}?messageId=${props.message.id}`;
  copyTextToClipboard(url);
  useAlert(t('INTERNAL_CHAT.MESSAGE.LINK_COPIED'));
}

function handleAddReaction(emoji) {
  emit('addReaction', { messageId: props.message.id, emoji });
}

function handleRemoveReaction(reactionId) {
  emit('removeReaction', {
    messageId: props.message.id,
    reactionId,
  });
}

function handleVote(payload) {
  emit('vote', payload);
}

function handleUnvote(payload) {
  emit('unvote', payload);
}
</script>

<template>
  <div
    class="group flex items-start gap-3 px-4 py-1.5 hover:bg-n-alpha-1 transition-colors"
  >
    <div class="flex-shrink-0 pt-0.5">
      <Avatar :name="senderName" :src="senderAvatar" :size="32" />
    </div>
    <div class="flex-1 min-w-0">
      <div class="flex items-baseline gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ senderName }}
        </span>
        <time class="text-xs text-n-slate-10">{{ timestamp }}</time>
        <span v-if="isEdited" class="text-xs text-n-slate-10">
          {{ t('INTERNAL_CHAT.MESSAGE.EDITED') }}
        </span>
        <span
          v-if="isPinned"
          class="flex items-center gap-1 text-xs text-n-amber-11"
          :title="t('INTERNAL_CHAT.PIN.PINNED_MESSAGE')"
        >
          <Icon icon="i-lucide-pin" class="size-3" />
        </span>
      </div>

      <!-- Poll content -->
      <div v-if="isPoll && !isDeleted" class="mt-1">
        <PollDisplay
          :message="message"
          :current-user-id="currentUserId"
          :is-admin="isAdmin"
          @vote="handleVote"
          @unvote="handleUnvote"
        />
      </div>

      <!-- Regular message content -->
      <div v-else class="mt-0.5 text-sm text-n-slate-12 break-words">
        <div
          v-if="isDeleted"
          class="flex items-center gap-1.5 rounded-lg bg-n-alpha-1 px-3 py-2 text-n-slate-10"
        >
          <Icon icon="i-lucide-trash-2" class="size-3.5 flex-shrink-0" />
          <span class="italic">{{ messageContent }}</span>
        </div>
        <div
          v-else
          v-dompurify-html="renderedContent"
          class="prose prose-bubble"
        />
      </div>

      <!-- Attachments -->
      <div v-if="attachments.length" class="mt-1.5 flex flex-wrap gap-2">
        <a
          v-for="attachment in attachments"
          :key="attachment.id"
          :href="attachment.file_url || attachment.external_url"
          target="_blank"
          rel="noopener noreferrer"
          class="flex items-center gap-1.5 rounded-lg border border-n-slate-6 bg-n-alpha-1 px-2.5 py-1.5 text-xs text-n-slate-12 hover:bg-n-alpha-2"
        >
          <Icon icon="i-lucide-paperclip" class="size-3.5 text-n-slate-10" />
          <span class="max-w-48 truncate">
            {{ attachment.file_url?.split('/').pop() || 'File' }}
          </span>
        </a>
      </div>

      <ReactionDisplay
        :reactions="reactions"
        :current-user-id="currentUserId"
        @remove="handleRemoveReaction"
      />

      <!-- Thread reply count -->
      <button
        v-if="threadReplyCount > 0"
        class="mt-1 flex items-center gap-1 text-xs font-medium text-n-brand hover:underline"
        @click="handleOpenThread"
      >
        <Icon icon="i-lucide-message-square" class="size-3" />
        {{ t('INTERNAL_CHAT.THREAD.REPLIES', { count: threadReplyCount }) }}
      </button>
    </div>
    <div
      v-if="!isDeleted"
      class="flex items-center gap-0.5 flex-shrink-0 opacity-0 group-hover:opacity-100 group-focus-within:opacity-100 transition-opacity"
    >
      <EmojiReactionPicker
        :reactions="reactions"
        :current-user-id="currentUserId"
        @select="handleAddReaction"
        @remove="handleRemoveReaction"
      />
      <button
        class="flex items-center justify-center rounded p-1 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :title="t('INTERNAL_CHAT.MESSAGE.REPLY')"
        @click="handleReply"
      >
        <Icon icon="i-lucide-reply" class="size-4" />
      </button>
      <button
        class="flex items-center justify-center rounded p-1 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :title="t('INTERNAL_CHAT.MESSAGE.COPY_LINK')"
        @click="handleCopyLink"
      >
        <Icon icon="i-lucide-link" class="size-4" />
      </button>
      <button
        v-if="canPin"
        class="flex items-center justify-center rounded p-1 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :title="
          isPinned ? t('INTERNAL_CHAT.PIN.UNPIN') : t('INTERNAL_CHAT.PIN.PIN')
        "
        @click="handlePin"
      >
        <Icon
          :icon="isPinned ? 'i-lucide-pin-off' : 'i-lucide-pin'"
          class="size-4"
        />
      </button>
      <button
        v-if="canEdit"
        class="flex items-center justify-center rounded p-1 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :title="t('INTERNAL_CHAT.MESSAGE.EDIT')"
        @click="handleEdit"
      >
        <Icon icon="i-lucide-pencil" class="size-4" />
      </button>
      <button
        v-if="canDelete"
        class="flex items-center justify-center rounded p-1 text-n-slate-11 hover:bg-n-ruby-3 hover:text-n-ruby-11"
        :title="t('INTERNAL_CHAT.MESSAGE.DELETE')"
        @click="handleDelete"
      >
        <Icon icon="i-lucide-trash-2" class="size-4" />
      </button>
    </div>

    <Dialog
      ref="deleteDialogRef"
      type="alert"
      :title="t('INTERNAL_CHAT.MESSAGE.DELETE')"
      :description="t('INTERNAL_CHAT.MESSAGE.CONFIRM_DELETE')"
      :confirm-button-label="t('INTERNAL_CHAT.MESSAGE.DELETE')"
      @confirm="confirmDelete"
    />
  </div>
</template>
