<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ReactionDisplay from './ReactionDisplay.vue';
import EmojiReactionPicker from './EmojiReactionPicker.vue';

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
  'addReaction',
  'removeReaction',
]);

const { t } = useI18n();

const isHovered = ref(false);

const senderName = computed(() => {
  return props.message.sender?.name || '';
});

const senderAvatar = computed(() => {
  return props.message.sender?.avatar_url || '';
});

const timestamp = computed(() => {
  return messageTimestamp(props.message.created_at, 'h:mm a');
});

const isOwnMessage = computed(() => {
  return props.message.sender?.id === props.currentUserId;
});

const isEdited = computed(() => {
  return props.message.edited;
});

const isDeleted = computed(() => {
  return props.message.deleted;
});

const canEdit = computed(() => {
  return isOwnMessage.value && !isDeleted.value;
});

const canDelete = computed(() => {
  return (isOwnMessage.value || props.isAdmin) && !isDeleted.value;
});

const messageContent = computed(() => {
  if (isDeleted.value) {
    return t('INTERNAL_CHAT.MESSAGE.DELETED');
  }
  return props.message.content || '';
});

const reactions = computed(() => {
  return props.message.reactions || [];
});

function handleEdit() {
  emit('edit', props.message);
}

function handleDelete() {
  emit('delete', props.message);
}

function handleReply() {
  emit('reply', props.message);
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
</script>

<template>
  <div
    class="group flex items-start gap-3 px-4 py-1.5 hover:bg-n-alpha-1 transition-colors"
    @mouseenter="isHovered = true"
    @mouseleave="isHovered = false"
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
      </div>
      <div
        class="mt-0.5 text-sm text-n-slate-12 break-words"
        :class="{ 'italic text-n-slate-10': isDeleted }"
      >
        <div v-if="!isDeleted" v-dompurify-html="messageContent" />
        <span v-else>{{ messageContent }}</span>
      </div>
      <ReactionDisplay
        :reactions="reactions"
        :current-user-id="currentUserId"
        @add="handleAddReaction"
        @remove="handleRemoveReaction"
      />
    </div>
    <div
      v-if="isHovered && !isDeleted"
      class="flex items-center gap-0.5 flex-shrink-0 opacity-0 group-hover:opacity-100 transition-opacity"
    >
      <EmojiReactionPicker @select="handleAddReaction" />
      <button
        class="flex items-center justify-center rounded p-1 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :title="t('INTERNAL_CHAT.MESSAGE.REPLY')"
        @click="handleReply"
      >
        <Icon icon="i-lucide-reply" class="size-4" />
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
  </div>
</template>
