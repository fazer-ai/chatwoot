<script setup>
import { ref, computed, onMounted, nextTick, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import MessageBubble from './MessageBubble.vue';

const props = defineProps({
  messages: {
    type: Array,
    default: () => [],
  },
  currentUserId: {
    type: Number,
    required: true,
  },
  isAdmin: {
    type: Boolean,
    default: false,
  },
  isLoading: {
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
  'loadMore',
]);

const { t } = useI18n();

const listRef = ref(null);
const showScrollToBottom = ref(false);

const dateSeparatedMessages = computed(() => {
  const groups = [];
  let currentDate = null;

  props.messages.forEach(message => {
    const msgDate = new Date(message.created_at * 1000);
    const dateKey = msgDate.toDateString();

    if (dateKey !== currentDate) {
      currentDate = dateKey;
      groups.push({ type: 'date', date: msgDate, key: `date-${dateKey}` });
    }
    groups.push({ type: 'message', data: message, key: `msg-${message.id}` });
  });

  return groups;
});

function formatDateSeparator(date) {
  const today = new Date();
  const yesterday = new Date(today);
  yesterday.setDate(yesterday.getDate() - 1);

  if (date.toDateString() === today.toDateString()) {
    return t('INTERNAL_CHAT.DATE_SEPARATOR.TODAY');
  }
  if (date.toDateString() === yesterday.toDateString()) {
    return t('INTERNAL_CHAT.DATE_SEPARATOR.YESTERDAY');
  }
  return date.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: date.getFullYear() !== today.getFullYear() ? 'numeric' : undefined,
  });
}

function scrollToBottom() {
  if (!listRef.value) return;
  listRef.value.scrollTop = listRef.value.scrollHeight;
}

function handleScroll() {
  if (!listRef.value) return;
  const { scrollTop, scrollHeight, clientHeight } = listRef.value;
  showScrollToBottom.value = scrollHeight - scrollTop - clientHeight > 100;

  if (scrollTop === 0 && props.messages.length > 0) {
    emit('loadMore');
  }
}

watch(
  () => props.messages.length,
  async (newLen, oldLen) => {
    if (newLen > oldLen) {
      const lastMsg = props.messages[props.messages.length - 1];
      const isOwnMessage = lastMsg?.sender?.id === props.currentUserId;

      if (isOwnMessage || !showScrollToBottom.value) {
        await nextTick();
        scrollToBottom();
      }
    }
  }
);

onMounted(async () => {
  await nextTick();
  scrollToBottom();
});
</script>

<template>
  <div class="relative flex-1 overflow-hidden">
    <div ref="listRef" class="h-full overflow-y-auto" @scroll="handleScroll">
      <div v-if="isLoading" class="flex items-center justify-center py-4">
        <Spinner :size="16" />
        <span class="ml-2 text-xs text-n-slate-10">
          {{ t('INTERNAL_CHAT.LOADING_MESSAGES') }}
        </span>
      </div>
      <div
        v-if="messages.length === 0 && !isLoading"
        class="flex h-full items-center justify-center"
      >
        <p class="text-sm text-n-slate-10">
          {{ t('INTERNAL_CHAT.CHANNEL.NO_MESSAGES') }}
        </p>
      </div>
      <template v-for="item in dateSeparatedMessages" :key="item.key">
        <div
          v-if="item.type === 'date'"
          class="flex items-center gap-3 px-4 py-2"
        >
          <div class="flex-1 border-t border-n-slate-5" />
          <span class="text-xs font-medium text-n-slate-10">
            {{ formatDateSeparator(item.date) }}
          </span>
          <div class="flex-1 border-t border-n-slate-5" />
        </div>
        <MessageBubble
          v-else
          :message="item.data"
          :current-user-id="currentUserId"
          :is-admin="isAdmin"
          @edit="emit('edit', $event)"
          @delete="emit('delete', $event)"
          @reply="emit('reply', $event)"
          @add-reaction="emit('addReaction', $event)"
          @remove-reaction="emit('removeReaction', $event)"
        />
      </template>
    </div>
    <button
      v-if="showScrollToBottom"
      class="absolute bottom-4 right-4 flex items-center justify-center rounded-full bg-n-solid-3 p-2 shadow-md border border-n-slate-6 text-n-slate-11 hover:bg-n-solid-4 hover:text-n-slate-12 transition-colors"
      :title="t('INTERNAL_CHAT.SCROLL_TO_BOTTOM')"
      @click="scrollToBottom"
    >
      <Icon icon="i-lucide-arrow-down" class="size-4" />
    </button>
  </div>
</template>
