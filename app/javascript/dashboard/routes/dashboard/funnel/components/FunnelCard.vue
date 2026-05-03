<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStoreGetters } from 'dashboard/composables/store';

const props = defineProps({
  conversation: { type: Object, required: true },
});

const { t } = useI18n();
const router = useRouter();
const getters = useStoreGetters();

const accountId = computed(() => getters.getCurrentAccountId.value);

const showSummary = ref(false);

const inboxName = computed(() => props.conversation.inbox?.name || '');
const contactName = computed(() => props.conversation.contact?.name || '');
const phoneNumber = computed(
  () => props.conversation.contact?.phone_number || ''
);
const aiEnabled = computed(() => props.conversation.ai_enabled !== false);
const summary = computed(() =>
  (props.conversation.summary || '').toString().trim()
);
const hasSummary = computed(() => summary.value.length > 0);

const elapsedLabel = computed(() => {
  const createdAtSec = Number(props.conversation.created_at) || 0;
  if (!createdAtSec) return '';
  const nowSec = Math.floor(Date.now() / 1000);
  const diff = Math.max(0, nowSec - createdAtSec);
  const hours = Math.floor(diff / 3600);
  if (hours < 24) return t('FUNNEL.CARD.ELAPSED_HOURS', { hours });
  const days = Math.floor(hours / 24);
  const remainingHours = hours - days * 24;
  return t('FUNNEL.CARD.ELAPSED_DAYS_HOURS', {
    days,
    hours: remainingHours,
  });
});

const goToContact = () => {
  if (!props.conversation.contact?.id) return;
  router.push({
    name: 'contacts_edit',
    params: {
      accountId: accountId.value,
      contactId: props.conversation.contact.id,
    },
  });
};

const goToConversation = () => {
  if (!props.conversation.id) return;
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: accountId.value,
      conversation_id: props.conversation.id,
    },
  });
};

const toggleSummary = () => {
  if (!hasSummary.value) return;
  showSummary.value = !showSummary.value;
};
</script>

<template>
  <article
    class="flex flex-col gap-2 px-3 py-2.5 bg-n-surface-1 border border-n-weak rounded-lg shadow-sm cursor-grab active:cursor-grabbing hover:border-n-slate-6"
  >
    <header class="flex items-center justify-between gap-2">
      <span class="text-xs font-medium text-n-slate-11">
        #{{ conversation.id }}
      </span>
      <span
        :class="aiEnabled ? 'bg-n-teal-9 text-white' : 'bg-n-ruby-9 text-white'"
        class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-medium"
      >
        <span class="size-1.5 rounded-full bg-white" />
        {{ aiEnabled ? t('FUNNEL.CARD.AI_ON') : t('FUNNEL.CARD.AI_OFF') }}
      </span>
    </header>

    <div class="flex flex-col gap-0.5">
      <span class="text-xs text-n-slate-11 truncate" :title="inboxName">
        {{ inboxName }}
      </span>
      <span
        class="text-sm font-medium text-n-slate-12 truncate"
        :title="contactName"
      >
        {{ contactName }}
      </span>
      <span v-if="phoneNumber" class="text-xs text-n-slate-11">
        {{ phoneNumber }}
      </span>
    </div>

    <footer class="flex items-center justify-between gap-2 mt-auto">
      <span
        v-if="elapsedLabel"
        class="inline-flex items-center gap-1 text-[11px] text-n-slate-11"
      >
        <span class="i-lucide-flag size-3" />
        {{ elapsedLabel }}
      </span>
      <div class="flex items-center gap-1">
        <button
          v-if="hasSummary"
          type="button"
          class="inline-flex items-center justify-center size-9 rounded text-n-blue-11 hover:bg-n-alpha-2"
          :aria-label="t('FUNNEL.CARD.SHOW_SUMMARY')"
          :title="t('FUNNEL.CARD.SHOW_SUMMARY')"
          @click="toggleSummary"
        >
          <span class="i-lucide-message-square-quote size-8" />
        </button>
        <button
          type="button"
          class="inline-flex items-center justify-center size-9 rounded text-n-slate-11 hover:bg-n-alpha-2"
          :aria-label="t('FUNNEL.CARD.OPEN_CONVERSATION')"
          :title="t('FUNNEL.CARD.OPEN_CONVERSATION')"
          @click="goToConversation"
        >
          <span class="i-lucide-message-circle size-8" />
        </button>
        <button
          type="button"
          class="inline-flex items-center justify-center size-9 rounded text-n-slate-11 hover:bg-n-alpha-2"
          :aria-label="t('FUNNEL.CARD.OPEN_CONTACT')"
          :title="t('FUNNEL.CARD.OPEN_CONTACT')"
          @click="goToContact"
        >
          <span class="i-lucide-user size-8" />
        </button>
      </div>
    </footer>

    <div
      v-if="showSummary && hasSummary"
      class="flex items-start gap-2 px-2.5 py-2 mt-1 rounded-md bg-n-slate-3 dark:bg-n-solid-3"
    >
      <span
        class="i-lucide-message-square-quote size-3 mt-0.5 flex-shrink-0 text-n-blue-11"
      />
      <p class="m-0 text-[11px] leading-snug text-n-blue-11">
        {{ summary }}
      </p>
    </div>
  </article>
</template>
