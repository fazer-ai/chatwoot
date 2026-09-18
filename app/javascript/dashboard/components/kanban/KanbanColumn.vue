<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import KanbanCard from './KanbanCard.vue';

defineProps({
  column: { type: Object, required: true },
  conversations: { type: Array, default: () => [] },
});

const emit = defineEmits(['moveCard', 'exportColumn']);
const { t } = useI18n();
const isOver = ref(false);

const onDrop = (event, targetStatus) => {
  isOver.value = false;
  const conversationId = Number(event.dataTransfer.getData('text/plain'));
  if (conversationId) emit('moveCard', { conversationId, targetStatus });
};
</script>

<template>
  <section
    class="flex flex-col w-80 h-full rounded-xl border shrink-0 bg-n-solid-2 border-n-weak"
    :class="{ 'outline outline-2 outline-n-brand': isOver }"
    @dragover.prevent="isOver = true"
    @dragleave="isOver = false"
    @drop.prevent="onDrop($event, column.id)"
  >
    <header
      class="flex justify-between items-center px-4 py-3 border-b border-n-weak"
    >
      <div class="flex gap-2 items-center min-w-0">
        <span class="size-2.5 rounded-full shrink-0" :class="column.dotClass" />
        <h2 class="font-medium truncate text-n-slate-12">{{ column.title }}</h2>
        <span
          class="px-2 py-0.5 text-xs rounded-full bg-n-alpha-2 text-n-slate-11"
        >
          {{ conversations.length }}
        </span>
      </div>
      <Button
        ghost
        slate
        sm
        :title="t('KANBAN.EXPORT.BUTTON')"
        @click="emit('exportColumn', column.id)"
      >
        <Icon icon="i-lucide-download" class="size-4" />
      </Button>
    </header>

    <div class="flex-1 p-3 space-y-3 min-h-48 overflow-y-auto">
      <KanbanCard
        v-for="conversation in conversations"
        :key="conversation.id"
        :conversation="conversation"
      />
      <div
        v-if="!conversations.length"
        class="flex flex-col gap-2 justify-center items-center py-10 text-n-slate-9"
      >
        <Icon icon="i-lucide-inbox" class="size-5" />
        <p class="text-sm">{{ t('KANBAN.EMPTY_COLUMN') }}</p>
      </div>
    </div>
  </section>
</template>
