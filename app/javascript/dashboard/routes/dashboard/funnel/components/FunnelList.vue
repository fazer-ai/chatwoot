<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStoreGetters } from 'dashboard/composables/store';
import { formatCurrency } from '../funnelFormatters';

const props = defineProps({
  stages: { type: Array, required: true },
  conversationsByStage: { type: Object, required: true },
  averageTicket: { type: Number, default: 0 },
  locale: { type: String, default: 'en' },
});

const { t } = useI18n();
const router = useRouter();
const getters = useStoreGetters();

const accountId = computed(() => getters.getCurrentAccountId.value);

const collapsed = ref({});
const expandedSummaries = ref({});

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
  if (!props.averageTicket) return countLabel;
  const sum = formatCurrency(count * props.averageTicket, props.locale);
  return `${sum} · ${countLabel}`;
};

const ticketLabel = computed(() =>
  props.averageTicket ? formatCurrency(props.averageTicket, props.locale) : ''
);

const elapsedLabelFor = conversation => {
  const createdAtSec = Number(conversation.created_at) || 0;
  if (!createdAtSec) return '';
  const nowSec = Math.floor(Date.now() / 1000);
  const diff = Math.max(0, nowSec - createdAtSec);
  const hours = Math.floor(diff / 3600);
  if (hours < 24) return t('FUNNEL.CARD.ELAPSED_HOURS', { hours });
  const days = Math.floor(hours / 24);
  return t('FUNNEL.CARD.ELAPSED_DAYS_HOURS', {
    days,
    hours: hours - days * 24,
  });
};

const toggle = stageName => {
  collapsed.value = {
    ...collapsed.value,
    [stageName]: !collapsed.value[stageName],
  };
};

const summaryFor = conversation =>
  (conversation.summary || '').toString().trim();
const hasSummary = conversation => summaryFor(conversation).length > 0;
const isSummaryOpen = conversation =>
  Boolean(expandedSummaries.value[conversation.id]);

const toggleSummary = conversation => {
  if (!hasSummary(conversation)) return;
  expandedSummaries.value = {
    ...expandedSummaries.value,
    [conversation.id]: !expandedSummaries.value[conversation.id],
  };
};

const goToConversation = conversation => {
  if (!conversation.id) return;
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: accountId.value,
      conversation_id: conversation.id,
    },
  });
};

const goToContact = conversation => {
  if (!conversation.contact?.id) return;
  router.push({
    name: 'contacts_edit',
    params: {
      accountId: accountId.value,
      contactId: conversation.contact.id,
    },
  });
};
</script>

<template>
  <div class="flex-1 min-h-0 overflow-y-auto px-6 py-4">
    <div class="flex flex-col gap-3 max-w-5xl">
      <section
        v-for="stage in orderedStages"
        :key="stage.id"
        class="rounded-lg border border-n-weak bg-n-surface-1 overflow-hidden"
      >
        <button
          type="button"
          class="flex items-center justify-between gap-3 w-full px-4 py-2.5 text-left hover:bg-n-alpha-2"
          @click="toggle(stage.name)"
        >
          <div class="flex items-center gap-2 min-w-0 flex-1">
            <span
              class="i-lucide-chevron-down size-4 text-n-slate-11 transition-transform flex-shrink-0"
              :class="{ '-rotate-90': collapsed[stage.name] }"
            />
            <span
              class="inline-block size-3 rounded-full flex-shrink-0"
              :style="{ backgroundColor: stage.color || '#94a3b8' }"
            />
            <div class="flex flex-col min-w-0">
              <span
                v-tooltip.top="stage.description"
                class="text-sm font-medium text-n-slate-12 truncate"
                :class="{ 'cursor-help': stage.description }"
              >
                {{ stage.name }}
              </span>
              <span class="text-xs text-n-slate-11 truncate">
                {{ stageSummary(stage) }}
              </span>
            </div>
          </div>
        </button>
        <div v-if="!collapsed[stage.name]" class="border-t border-n-weak">
          <table class="w-full text-sm">
            <thead class="bg-n-alpha-1">
              <tr class="text-left text-xs text-n-slate-11">
                <th class="px-4 py-2 font-medium">
                  {{ t('FUNNEL.LIST.CONTACT') }}
                </th>
                <th class="px-4 py-2 font-medium">
                  {{ t('FUNNEL.LIST.PHONE') }}
                </th>
                <th class="px-4 py-2 font-medium">
                  {{ t('FUNNEL.LIST.INBOX') }}
                </th>
                <th class="px-4 py-2 font-medium">{{ t('FUNNEL.LIST.AI') }}</th>
                <th class="px-4 py-2 font-medium">
                  {{ t('FUNNEL.LIST.VALUE') }}
                </th>
                <th class="px-4 py-2 font-medium">
                  {{ t('FUNNEL.LIST.ELAPSED') }}
                </th>
                <th class="px-4 py-2 font-medium text-right">
                  {{ t('FUNNEL.LIST.ACTIONS') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <template
                v-for="conversation in cardsFor(stage)"
                :key="conversation.id"
              >
                <tr class="border-t border-n-weak hover:bg-n-alpha-1">
                  <td class="px-4 py-2 font-medium text-n-slate-12">
                    {{ conversation.contact?.name }}
                  </td>
                  <td class="px-4 py-2 text-n-slate-11">
                    {{ conversation.contact?.phone_number }}
                  </td>
                  <td class="px-4 py-2 text-n-slate-11">
                    {{ conversation.inbox?.name }}
                  </td>
                  <td class="px-4 py-2">
                    <span
                      :class="
                        conversation.ai_enabled !== false
                          ? 'bg-n-teal-9 text-white'
                          : 'bg-n-ruby-9 text-white'
                      "
                      class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-medium"
                    >
                      <span class="size-1.5 rounded-full bg-white" />
                      {{
                        conversation.ai_enabled !== false
                          ? t('FUNNEL.CARD.AI_ON')
                          : t('FUNNEL.CARD.AI_OFF')
                      }}
                    </span>
                  </td>
                  <td class="px-4 py-2 text-n-slate-12">
                    {{ ticketLabel }}
                  </td>
                  <td class="px-4 py-2 text-n-slate-11">
                    {{ elapsedLabelFor(conversation) }}
                  </td>
                  <td class="px-4 py-2">
                    <div class="flex items-center justify-end gap-1">
                      <button
                        v-if="hasSummary(conversation)"
                        type="button"
                        class="inline-flex items-center justify-center size-8 rounded text-n-blue-11 hover:bg-n-alpha-2"
                        :aria-label="t('FUNNEL.CARD.SHOW_SUMMARY')"
                        :title="t('FUNNEL.CARD.SHOW_SUMMARY')"
                        @click="toggleSummary(conversation)"
                      >
                        <span class="i-lucide-message-square-quote size-8" />
                      </button>
                      <button
                        type="button"
                        class="inline-flex items-center justify-center size-8 rounded text-n-slate-11 hover:bg-n-alpha-2"
                        :aria-label="t('FUNNEL.CARD.OPEN_CONVERSATION')"
                        :title="t('FUNNEL.CARD.OPEN_CONVERSATION')"
                        @click="goToConversation(conversation)"
                      >
                        <span class="i-lucide-message-circle size-8" />
                      </button>
                      <button
                        type="button"
                        class="inline-flex items-center justify-center size-8 rounded text-n-slate-11 hover:bg-n-alpha-2"
                        :aria-label="t('FUNNEL.CARD.OPEN_CONTACT')"
                        :title="t('FUNNEL.CARD.OPEN_CONTACT')"
                        @click="goToContact(conversation)"
                      >
                        <span class="i-lucide-user size-8" />
                      </button>
                    </div>
                  </td>
                </tr>
                <tr
                  v-if="isSummaryOpen(conversation) && hasSummary(conversation)"
                  class="border-t border-n-weak bg-n-slate-2 dark:bg-n-solid-2"
                >
                  <td colspan="7" class="px-4 py-3">
                    <div
                      class="flex items-start gap-2 px-3 py-2 rounded-md bg-n-slate-3 dark:bg-n-solid-3"
                    >
                      <span
                        class="i-lucide-message-square-quote size-4 mt-0.5 flex-shrink-0 text-n-blue-11"
                      />
                      <p class="m-0 text-xs leading-snug text-n-blue-11">
                        {{ summaryFor(conversation) }}
                      </p>
                    </div>
                  </td>
                </tr>
              </template>
              <tr v-if="cardsFor(stage).length === 0">
                <td
                  colspan="7"
                  class="px-4 py-6 text-center text-xs text-n-slate-11"
                >
                  {{ t('FUNNEL.LIST.EMPTY') }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
  </div>
</template>
