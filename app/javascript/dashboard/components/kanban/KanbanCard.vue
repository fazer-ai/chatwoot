<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  conversation: { type: Object, required: true },
});

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const contact = computed(() => props.conversation.contact || {});
const contactAttributes = computed(() => contact.value.custom_attributes || {});
const leadScore = computed(
  () => Number(contactAttributes.value.lead_score) || 0
);
const temperature = computed(() => {
  const value = contactAttributes.value.temperatura;
  return ['quente', 'morno', 'frio'].includes(value) ? value : 'frio';
});
const temperatureEmoji = computed(
  () => ({ quente: '🔥', morno: '☀️', frio: '❄️' })[temperature.value] || '❄️'
);
const temperatureLabel = computed(
  () =>
    ({
      quente: t('KANBAN.TEMPERATURE.QUENTE'),
      morno: t('KANBAN.TEMPERATURE.MORNO'),
      frio: t('KANBAN.TEMPERATURE.FRIO'),
    })[temperature.value]
);
const scoreClasses = computed(() => {
  if (leadScore.value >= 70) return 'bg-n-teal-3 text-n-teal-11';
  if (leadScore.value >= 40) return 'bg-n-amber-3 text-n-amber-11';
  return 'bg-n-ruby-3 text-n-ruby-11';
});
const lastActivity = computed(() => {
  if (!props.conversation.last_activity_at) return t('KANBAN.CARD.NO_ACTIVITY');
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(props.conversation.last_activity_at));
});

const onDragStart = event => {
  event.dataTransfer.effectAllowed = 'move';
  event.dataTransfer.setData('text/plain', String(props.conversation.id));
};

const openConversation = () => {
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: route.params.accountId,
      conversation_id: props.conversation.id,
    },
  });
};
</script>

<template>
  <article
    class="p-4 rounded-xl border cursor-pointer bg-n-solid-1 border-n-weak hover:border-n-strong hover:shadow-sm"
    draggable="true"
    @dragstart="onDragStart"
    @click="openConversation"
  >
    <div class="flex gap-3 justify-between items-start">
      <div class="min-w-0">
        <h3 class="font-medium truncate text-n-slate-12">
          {{ contact.name || t('KANBAN.CARD.UNNAMED') }}
        </h3>
        <p class="mt-0.5 text-xs truncate text-n-slate-10">
          {{ contact.phone_number || t('KANBAN.CARD.NO_PHONE') }}
        </p>
      </div>
      <div class="flex gap-1.5 items-center shrink-0">
        <span :title="temperatureLabel">
          {{ temperatureEmoji }}
        </span>
        <span
          class="px-2 py-0.5 text-xs font-semibold rounded-full"
          :class="scoreClasses"
        >
          {{ leadScore }}
        </span>
      </div>
    </div>

    <p
      v-if="contactAttributes.servico_interesse"
      class="mt-3 text-sm line-clamp-2 text-n-slate-11"
    >
      {{ contactAttributes.servico_interesse }}
    </p>

    <div
      class="flex gap-2 justify-between items-center pt-3 mt-3 border-t border-n-weak"
    >
      <span class="flex gap-1 items-center text-xs text-n-slate-10">
        <Icon icon="i-lucide-message-circle" class="size-3.5" />
        {{
          t('KANBAN.CARD.MESSAGE_COUNT', {
            count: conversation.messages_count || 0,
          })
        }}
      </span>
      <span class="text-xs text-n-slate-10">{{ lastActivity }}</span>
    </div>
  </article>
</template>
