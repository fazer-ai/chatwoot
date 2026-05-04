<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStoreGetters } from 'dashboard/composables/store';
import { debounce } from '@chatwoot/utils';
import FunnelAPI from 'dashboard/api/funnel';

import FunnelBoard from './components/FunnelBoard.vue';
import FunnelList from './components/FunnelList.vue';
import FunnelFilters from './components/FunnelFilters.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const { t } = useI18n();
const getters = useStoreGetters();

const VIEW_MODES = ['board', 'list'];
const viewMode = ref('board');

const isLoading = ref(false);
const stages = ref([]);
const conversationsByStage = ref({});

const accountId = computed(() => getters.getCurrentAccountId.value);
const account = computed(() =>
  getters['accounts/getAccount'].value(accountId.value)
);
const accountLocale = computed(() => account.value?.locale || 'en');
const accountAverageTicket = computed(
  () => Number(account.value?.average_ticket) || 0
);

const filters = ref({
  inboxId: '',
  fromDate: '',
  toDate: '',
  hideClosed: false,
});

const setViewMode = mode => {
  if (!VIEW_MODES.includes(mode)) return;
  viewMode.value = mode;
};

const buildQueryParams = () => {
  const params = {};
  if (filters.value.inboxId) params.inbox_id = filters.value.inboxId;
  if (filters.value.fromDate)
    params.from = `${filters.value.fromDate}T00:00:00`;
  if (filters.value.toDate) params.to = `${filters.value.toDate}T23:59:59`;
  if (filters.value.hideClosed) params.hide_closed = 'true';
  return params;
};

const fetchFunnel = async () => {
  isLoading.value = true;
  try {
    const { data } = await FunnelAPI.get(buildQueryParams());
    stages.value = data?.payload?.stages || [];
    const grouped = {};
    stages.value.forEach(stage => {
      grouped[stage.name] = stage.conversations || [];
    });
    conversationsByStage.value = grouped;
  } catch (error) {
    useAlert(t('FUNNEL.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const debouncedFetch = debounce(fetchFunnel, 300);

const moveConversation = async ({ conversationId, stage }) => {
  let sourceStageName = null;
  let movedConversation = null;

  Object.entries(conversationsByStage.value).some(([stageName, list]) => {
    const idx = list.findIndex(c => c.id === conversationId);
    if (idx === -1) return false;
    sourceStageName = stageName;
    movedConversation = list[idx];
    return true;
  });

  if (!movedConversation || sourceStageName === stage) return;

  conversationsByStage.value = {
    ...conversationsByStage.value,
    [sourceStageName]: conversationsByStage.value[sourceStageName].filter(
      c => c.id !== conversationId
    ),
    [stage]: [...(conversationsByStage.value[stage] || []), movedConversation],
  };

  stages.value = stages.value.map(s => {
    if (s.name === sourceStageName)
      return { ...s, count: Math.max(0, (s.count || 0) - 1) };
    if (s.name === stage) return { ...s, count: (s.count || 0) + 1 };
    return s;
  });

  try {
    await FunnelAPI.move({ conversationId, stage, source: 'web' });
  } catch (error) {
    useAlert(t('FUNNEL.MOVE.ERROR'));
    await fetchFunnel();
  }
};

const resetFilters = () => {
  filters.value = {
    inboxId: '',
    fromDate: '',
    toDate: '',
    hideClosed: false,
  };
};

const isEmpty = computed(() => !isLoading.value && stages.value.length === 0);

watch(filters, debouncedFetch, { deep: true });

onMounted(fetchFunnel);
</script>

<template>
  <section class="flex flex-col w-full h-full bg-n-surface-1">
    <header
      class="flex items-center justify-between gap-3 px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-heading-2 text-n-slate-12">
        {{ t('FUNNEL.TITLE') }}
      </h1>
      <div
        class="inline-flex items-center gap-1 p-1 rounded-lg bg-n-alpha-2"
        role="group"
        :aria-label="t('FUNNEL.VIEW_MODE.ARIA_LABEL')"
      >
        <button
          v-for="mode in VIEW_MODES"
          :key="mode"
          type="button"
          class="inline-flex items-center gap-1.5 px-3 py-1 rounded-md text-sm font-medium transition-colors"
          :class="
            viewMode === mode
              ? 'bg-n-surface-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="setViewMode(mode)"
        >
          <span
            :class="mode === 'board' ? 'i-lucide-columns-3' : 'i-lucide-list'"
            class="size-4"
          />
          {{ t(`FUNNEL.VIEW_MODE.${mode.toUpperCase()}`) }}
        </button>
      </div>
    </header>

    <FunnelFilters
      v-model:inbox-id="filters.inboxId"
      v-model:from-date="filters.fromDate"
      v-model:to-date="filters.toDate"
      v-model:hide-closed="filters.hideClosed"
      @reset="resetFilters"
    />

    <div
      v-if="isLoading"
      class="flex items-center justify-center flex-1 text-n-slate-11"
    >
      <Spinner />
    </div>

    <div
      v-else-if="isEmpty"
      class="flex items-center justify-center flex-1 text-n-slate-11 px-6 text-center"
    >
      {{ t('FUNNEL.EMPTY_STATE') }}
    </div>

    <FunnelBoard
      v-else-if="viewMode === 'board'"
      :stages="stages"
      :conversations-by-stage="conversationsByStage"
      :average-ticket="accountAverageTicket"
      :locale="accountLocale"
      @move="moveConversation"
    />

    <FunnelList
      v-else
      :stages="stages"
      :conversations-by-stage="conversationsByStage"
      :average-ticket="accountAverageTicket"
      :locale="accountLocale"
    />
  </section>
</template>
