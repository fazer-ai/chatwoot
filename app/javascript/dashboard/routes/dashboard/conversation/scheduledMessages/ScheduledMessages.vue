<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';

import ScheduledMessageItem from 'next/Contacts/ContactsSidebar/components/ScheduledMessageItem.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ScheduledMessageSkeletonLoader from './ScheduledMessageSkeletonLoader.vue';
import ScheduledMessageModal from './ScheduledMessageModal.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
  inboxId: {
    type: [Number, String],
    default: null,
  },
});

const { t } = useI18n();
const store = useStore();

const currentUser = useMapGetter('getCurrentUser');
const scheduledMessagesGetter = useMapGetter(
  'scheduledMessages/getAllByConversation'
);
const uiFlags = useMapGetter('scheduledMessages/getUIFlags');

const isFetching = computed(() => uiFlags.value.isFetching);
const isDeleting = computed(() => uiFlags.value.isDeleting);

const shouldShowModal = ref(false);
const editingMessage = ref(null);
const showDeleteConfirm = ref(false);
const messageToDelete = ref(null);

const scheduledMessages = computed(() => {
  if (!props.conversationId) return [];
  return scheduledMessagesGetter.value(props.conversationId) || [];
});

const draftMessages = computed(() =>
  scheduledMessages.value.filter(message => message.status === 'draft')
);

const pendingMessages = computed(() =>
  scheduledMessages.value
    .filter(message => message.status === 'pending')
    .sort((a, b) => (a.scheduled_at || 0) - (b.scheduled_at || 0))
);

const historyMessages = computed(() =>
  scheduledMessages.value
    .filter(message => ['sent', 'failed'].includes(message.status))
    .sort((a, b) => (b.scheduled_at || 0) - (a.scheduled_at || 0))
);

const hasActiveMessages = computed(
  () => draftMessages.value.length > 0 || pendingMessages.value.length > 0
);

const hasHistory = computed(() => historyMessages.value.length > 0);

const fetchScheduledMessages = conversationId => {
  if (!conversationId) return;
  store.dispatch('scheduledMessages/get', { conversationId });
};

const getWrittenBy = scheduledMessage => {
  const currentUserId = currentUser.value?.id;
  const author = scheduledMessage?.author;

  if (!author) return t('CONVERSATION.BOT');

  const authorName = author.name || t('CONVERSATION.BOT');
  if (author.id === currentUserId && scheduledMessage.author_type === 'User') {
    return t('SCHEDULED_MESSAGES.META.AUTHOR_YOU', { name: authorName });
  }

  return authorName;
};

const openCreateModal = () => {
  if (!props.conversationId) return;
  editingMessage.value = null;
  shouldShowModal.value = true;
};

const openEditModal = message => {
  editingMessage.value = message;
  shouldShowModal.value = true;
};

const closeModal = () => {
  shouldShowModal.value = false;
  editingMessage.value = null;
};

const openDeleteConfirm = message => {
  if (!props.conversationId || !message?.id || isDeleting.value) return;
  messageToDelete.value = message;
  showDeleteConfirm.value = true;
};

const closeDeleteConfirm = () => {
  showDeleteConfirm.value = false;
  messageToDelete.value = null;
};

const confirmDelete = async () => {
  if (!messageToDelete.value?.id) return;
  try {
    await store.dispatch('scheduledMessages/delete', {
      conversationId: props.conversationId,
      scheduledMessageId: messageToDelete.value.id,
    });
    closeDeleteConfirm();
  } catch (error) {
    useAlert(t('SCHEDULED_MESSAGES.ERRORS.DELETE_FAILED'));
  }
};

watch(
  () => props.conversationId,
  newConversationId => {
    fetchScheduledMessages(newConversationId);
  },
  { immediate: true }
);
</script>

<template>
  <div>
    <div class="flex items-center justify-between gap-2 px-4 pt-3 pb-2">
      <NextButton
        ghost
        xs
        icon="i-lucide-plus"
        :label="t('SCHEDULED_MESSAGES.NEW_BUTTON')"
        :disabled="!conversationId || isFetching"
        @click="openCreateModal"
      />
    </div>

    <ScheduledMessageSkeletonLoader v-if="isFetching" :rows="3" />

    <div v-else class="flex flex-col max-h-[400px] overflow-y-auto">
      <!-- Draft Messages -->
      <template v-if="draftMessages.length">
        <ScheduledMessageItem
          v-for="message in draftMessages"
          :key="message.id"
          class="px-4 py-4"
          :scheduled-message="message"
          :written-by="getWrittenBy(message)"
          allow-edit
          allow-delete
          collapsible
          @edit="openEditModal"
          @delete="openDeleteConfirm"
        />
      </template>

      <!-- Pending Messages -->
      <template v-if="pendingMessages.length">
        <ScheduledMessageItem
          v-for="message in pendingMessages"
          :key="message.id"
          class="px-4 py-4"
          :scheduled-message="message"
          :written-by="getWrittenBy(message)"
          allow-edit
          allow-delete
          collapsible
          @edit="openEditModal"
          @delete="openDeleteConfirm"
        />
      </template>

      <!-- Empty State for active messages -->
      <p
        v-if="!hasActiveMessages && !hasHistory"
        class="px-6 py-6 text-sm leading-6 text-center text-n-slate-11"
      >
        {{ t('SCHEDULED_MESSAGES.EMPTY_STATE') }}
      </p>

      <!-- History Section -->
      <template v-if="hasHistory">
        <div
          class="flex items-center gap-2 px-4 pt-4 pb-2 border-t border-n-weak"
        >
          <span class="text-xs font-medium text-n-slate-11 uppercase">
            {{ t('SCHEDULED_MESSAGES.PAST_MESSAGES_SECTION') }}
          </span>
        </div>
        <ScheduledMessageItem
          v-for="message in historyMessages"
          :key="message.id"
          class="px-4 py-4"
          :scheduled-message="message"
          :written-by="getWrittenBy(message)"
          :allow-edit="false"
          :allow-delete="false"
          collapsible
        />
      </template>
    </div>

    <ScheduledMessageModal
      v-model:show="shouldShowModal"
      :conversation-id="conversationId"
      :inbox-id="inboxId"
      :scheduled-message="editingMessage"
      @close="closeModal"
    />

    <woot-modal
      v-model:show="showDeleteConfirm"
      :on-close="closeDeleteConfirm"
      size="small"
    >
      <div class="flex w-full flex-col gap-4 px-6 py-6">
        <h3 class="text-lg font-semibold text-n-slate-12">
          {{ t('SCHEDULED_MESSAGES.CONFIRM_DELETE.TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11">
          {{ t('SCHEDULED_MESSAGES.CONFIRM_DELETE.MESSAGE') }}
        </p>
        <div class="flex items-center justify-end gap-3">
          <NextButton
            ghost
            slate
            :label="t('SCHEDULED_MESSAGES.CONFIRM_DELETE.CANCEL')"
            :disabled="isDeleting"
            @click="closeDeleteConfirm"
          />
          <NextButton
            solid
            ruby
            :label="t('SCHEDULED_MESSAGES.CONFIRM_DELETE.DELETE')"
            :is-loading="isDeleting"
            :disabled="isDeleting"
            @click="confirmDelete"
          />
        </div>
      </div>
    </woot-modal>
  </div>
</template>
