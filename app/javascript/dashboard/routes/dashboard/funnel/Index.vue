<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import FunnelAPI from 'dashboard/api/funnel';

import FunnelBoard from './components/FunnelBoard.vue';
import FunnelList from './components/FunnelList.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const { t } = useI18n();

const VIEW_MODES = ['board', 'list'];
const viewMode = ref('board');

const isLoading = ref(false);
const stages = ref([]);
const conversationsByStage = ref({});

const setViewMode = mode => {
  if (!VIEW_MODES.includes(mode)) return;
  viewMode.value = mode;
};

const fetchFunnel = async () => {
  isLoading.value = true;
  try {
    const { data } = await FunnelAPI.get();
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

const moveConversation = async ({ conversationId, stage }) => {
  try {
    await FunnelAPI.move({ conversationId, stage, source: 'web' });
    useAlert(t('FUNNEL.MOVE.SUCCESS', { stage }));
    await fetchFunnel();
  } catch (error) {
    useAlert(t('FUNNEL.MOVE.ERROR'));
    await fetchFunnel();
  }
};

const isEmpty = computed(() => !isLoading.value && stages.value.length === 0);

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
      @move="moveConversation"
    />

    <FunnelList
      v-else
      :stages="stages"
      :conversations-by-stage="conversationsByStage"
    />
  </section>
</template>
