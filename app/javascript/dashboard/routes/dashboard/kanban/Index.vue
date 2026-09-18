<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';

import KanbanAPI from 'dashboard/api/kanban';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import KanbanBoard from 'dashboard/components/kanban/KanbanBoard.vue';
import KanbanFilters from 'dashboard/components/kanban/KanbanFilters.vue';
import { useAlert } from 'dashboard/composables';

const { t } = useI18n();
const store = useStore();

const conversationsByStatus = ref({});
const stats = ref({ total: 0, by_temperatura: {} });
const meta = ref({ truncated: false });
const filters = ref({ search: '', temperatura: '', score: '', inbox_id: '' });
const isLoading = ref(false);
const movingConversationId = ref(null);

const inboxes = computed(() => store.getters['inboxes/getInboxes']);
const columns = computed(() => [
  {
    id: 'novo_lead',
    title: t('KANBAN.STATUS.NOVO_LEAD'),
    dotClass: 'bg-n-blue-9',
  },
  {
    id: 'aquecimento',
    title: t('KANBAN.STATUS.AQUECIMENTO'),
    dotClass: 'bg-n-amber-9',
  },
  {
    id: 'qualificado',
    title: t('KANBAN.STATUS.QUALIFICADO'),
    dotClass: 'bg-n-teal-9',
  },
  {
    id: 'convertido',
    title: t('KANBAN.STATUS.CONVERTIDO'),
    dotClass: 'bg-n-iris-9',
  },
  { id: 'perdido', title: t('KANBAN.STATUS.PERDIDO'), dotClass: 'bg-n-ruby-9' },
]);

const loadConversations = async () => {
  isLoading.value = true;
  try {
    const { data } = await KanbanAPI.getConversations(filters.value);
    conversationsByStatus.value = data.kanban_data;
    stats.value = data.stats;
    meta.value = data.meta;
  } catch {
    useAlert(t('KANBAN.API.ERROR.FETCH'));
  } finally {
    isLoading.value = false;
  }
};

const moveConversation = async ({ conversationId, targetStatus }) => {
  if (movingConversationId.value) return;

  movingConversationId.value = conversationId;
  try {
    await KanbanAPI.moveConversation(conversationId, targetStatus);
    await loadConversations();
    useAlert(t('KANBAN.API.SUCCESS.MOVE'));
  } catch {
    useAlert(t('KANBAN.API.ERROR.MOVE'));
  } finally {
    movingConversationId.value = null;
  }
};

const csvCell = value => `"${String(value ?? '').replaceAll('"', '""')}"`;
const exportColumn = async status => {
  try {
    const { data } = await KanbanAPI.exportConversations({
      ...filters.value,
      status,
    });
    if (!data.data.length) {
      useAlert(t('KANBAN.EXPORT.NO_DATA'));
      return;
    }

    const headers = Object.keys(data.data[0]);
    const rows = data.data.map(row =>
      headers.map(header => csvCell(row[header])).join(',')
    );
    const blob = new Blob(
      [`\uFEFF${[headers.join(','), ...rows].join('\n')}`],
      {
        type: 'text/csv;charset=utf-8',
      }
    );
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `kanban-${status}.csv`;
    link.click();
    URL.revokeObjectURL(url);
    useAlert(t('KANBAN.EXPORT.SUCCESS'));
  } catch {
    useAlert(t('KANBAN.EXPORT.ERROR'));
  }
};

onMounted(() => {
  loadConversations();
  store.dispatch('inboxes/get');
});
</script>

<template>
  <main class="flex flex-col w-full h-full min-h-0 bg-n-background">
    <header
      class="flex justify-between items-center px-5 py-4 border-b bg-n-solid-1 border-n-weak"
    >
      <div>
        <h1 class="text-xl font-semibold text-n-slate-12">
          {{ t('KANBAN.TITLE') }}
        </h1>
        <p class="mt-1 text-sm text-n-slate-10">
          {{ t('KANBAN.CONVERSATION_COUNT', { count: stats.total || 0 }) }}
        </p>
      </div>
      <Button
        outline
        slate
        md
        :is-loading="isLoading"
        @click="loadConversations"
      >
        <Icon icon="i-lucide-refresh-cw" class="mr-2 size-4" />
        {{ t('KANBAN.REFRESH') }}
      </Button>
    </header>

    <KanbanFilters
      v-model:filters="filters"
      :inboxes="inboxes"
      @apply="loadConversations"
    />

    <div
      v-if="meta.truncated"
      class="px-4 py-2 text-sm border-b bg-n-amber-3 text-n-amber-11 border-n-amber-6"
    >
      {{ t('KANBAN.LIMIT_NOTICE', { count: meta.limit }) }}
    </div>

    <div
      v-if="isLoading && !stats.total"
      class="flex flex-1 justify-center items-center"
    >
      <Spinner />
    </div>
    <KanbanBoard
      v-else
      :columns="columns"
      :conversations-by-status="conversationsByStatus"
      @move-card="moveConversation"
      @export-column="exportColumn"
    />
  </main>
</template>
