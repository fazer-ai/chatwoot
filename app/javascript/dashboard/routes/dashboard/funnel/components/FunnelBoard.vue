<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';

import FunnelCard from './FunnelCard.vue';
import { formatCurrency } from '../funnelFormatters';

const props = defineProps({
  stages: { type: Array, required: true },
  conversationsByStage: { type: Object, required: true },
  averageTicket: { type: Number, default: 0 },
  locale: { type: String, default: 'en' },
});

const emit = defineEmits(['move']);

const { t } = useI18n();

const orderedStages = computed(() =>
  [...props.stages].sort((a, b) => {
    if (a.position !== b.position) return a.position - b.position;
    return a.id - b.id;
  })
);

const cardsFor = stage => props.conversationsByStage[stage.name] || [];

const stageSummary = stage => {
  const count = stage.count || 0;
  const countLabel = t('FUNNEL.STAGE.COUNT_LABEL', count, { count });
  const sum = formatCurrency(count * props.averageTicket, props.locale);
  return `${sum} · ${countLabel}`;
};

const onDragEnd = (event, targetStage) => {
  if (!event?.added) return;
  const conversation = event.added.element;
  if (!conversation) return;
  emit('move', {
    conversationId: conversation.id,
    stage: targetStage.name,
  });
};
</script>

<template>
  <div class="flex-1 min-h-0 overflow-x-auto overflow-y-hidden px-6 py-4">
    <div class="flex items-stretch gap-3 h-full min-h-0">
      <section
        v-for="stage in orderedStages"
        :key="stage.id"
        class="flex flex-col w-[17rem] flex-shrink-0 bg-n-alpha-2 rounded-lg overflow-hidden"
      >
        <header class="flex flex-col gap-0.5 px-3 py-2 border-b border-n-weak">
          <div class="flex items-center gap-2 min-w-0">
            <span
              class="inline-block size-3 rounded-full flex-shrink-0"
              :style="{ backgroundColor: stage.color || '#94a3b8' }"
            />
            <span
              v-tooltip.top="stage.description"
              class="text-sm font-medium text-n-slate-12 truncate"
              :class="{ 'cursor-help': stage.description }"
            >
              {{ stage.name }}
            </span>
          </div>
          <span class="text-xs text-n-slate-11">
            {{ stageSummary(stage) }}
          </span>
        </header>

        <Draggable
          :model-value="cardsFor(stage)"
          :group="{ name: 'funnel', pull: true, put: true }"
          item-key="id"
          class="flex-1 flex flex-col gap-2 p-2 overflow-y-auto"
          ghost-class="opacity-50"
          @change="event => onDragEnd(event, stage)"
        >
          <template #item="{ element }">
            <FunnelCard :conversation="element" />
          </template>
        </Draggable>
      </section>
    </div>
  </div>
</template>
