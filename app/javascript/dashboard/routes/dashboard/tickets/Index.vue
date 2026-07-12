<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TicketDetailDialog from 'dashboard/components-next/feedback/TicketDetailDialog.vue';

// Meus Tickets. Renders every ticket the current user is allowed to see —
// TicketPolicy::Scope on the backend already trims the payload to "own for
// agent, everything for manager/admin", so this component doesn't need to
// duplicate that check; it only decides whether to show the "Agente" column
// and the (admin/manager-only) ClickUp link column.

const { t } = useI18n();
const store = useStore();

const records = useMapGetter('tickets/getRecords');
const meta = useMapGetter('tickets/getMeta');
const uiFlags = useMapGetter('tickets/getUIFlags');
const currentRole = useMapGetter('getCurrentRole');

const isAdminOrManager = computed(() =>
  ['administrator', 'manager'].includes(currentRole.value)
);

// ClickUp task links expose internal ops references (task id, workspace),
// so only administrators get that column — managers stay on the same "sees
// every ticket" scope for the rest of the row.
const isAdministrator = computed(() => currentRole.value === 'administrator');

// ClickUp team id is fixed for the Auris workspace (see FieldMap::TEAM_ID
// on the backend). We assemble the task URL client-side so the admin link
// column stays populated even for older tickets whose sync response landed
// the task id but not the URL (a state PR1 briefly allowed).
const CLICKUP_TEAM_ID = '90132001451';
const clickupTaskUrl = ticket => {
  if (ticket.clickup_task_url) return ticket.clickup_task_url;
  if (!ticket.clickup_task_id) return null;
  return `https://app.clickup.com/t/${CLICKUP_TEAM_ID}/${ticket.clickup_task_id}`;
};

const statusFilter = ref('');
const hideFinished = ref(false);
const currentPage = ref(1);
const detailDialogRef = ref(null);
const EMPTY_CELL = '—';

// Only three canonical statuses reach the frontend — the backend
// (Webhooks::Clickup::ProcessEventService) collapses ClickUp's ~7 raw
// statuses down to these before writing `clickup_status_name` on the
// ticket record.
const statusFilterOptions = computed(() => [
  { value: '', label: t('MEUS_TICKETS.FILTERS.ALL') },
  { value: 'aberto', label: t('MEUS_TICKETS.STATUS.ABERTO') },
  { value: 'em análise', label: t('MEUS_TICKETS.STATUS.EM_ANALISE') },
  { value: 'encerrado', label: t('MEUS_TICKETS.STATUS.ENCERRADO') },
]);

const tableHeaders = computed(() => {
  const headers = [
    t('MEUS_TICKETS.COLUMNS.DISPLAY_ID'),
    t('MEUS_TICKETS.COLUMNS.OPENED_AT'),
    t('MEUS_TICKETS.COLUMNS.PROBLEM'),
    t('MEUS_TICKETS.COLUMNS.STATUS'),
    t('MEUS_TICKETS.COLUMNS.RESPONSE'),
  ];
  if (isAdminOrManager.value) {
    headers.push(t('MEUS_TICKETS.COLUMNS.AGENT'));
  }
  if (isAdministrator.value) {
    headers.push(t('MEUS_TICKETS.COLUMNS.CLICKUP'));
  }
  return headers;
});

const fetch = async () => {
  await store.dispatch('tickets/fetchAll', {
    page: currentPage.value,
    status: statusFilter.value || undefined,
    hideFinished: hideFinished.value,
  });
};

const openTicket = ticket => {
  detailDialogRef.value?.openWith(ticket);
};

watch([statusFilter, hideFinished], () => {
  currentPage.value = 1;
  fetch();
});

const onPageChange = page => {
  currentPage.value = page;
  fetch();
};

const statusBadgeClass = statusName => {
  const slug = (statusName || '').toLowerCase();
  if (slug === 'encerrado') return 'bg-n-teal-3 text-n-teal-11';
  if (['em análise', 'em analise'].includes(slug))
    return 'bg-n-blue-3 text-n-blue-11';
  return 'bg-n-slate-3 text-n-slate-11';
};

const formatDate = timestamp => {
  if (!timestamp) return '';
  const date = new Date(timestamp);
  return date.toLocaleDateString(undefined, {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
};

const openClickupTask = (event, url) => {
  event.stopPropagation();
  if (url) window.open(url, '_blank');
};

onMounted(async () => {
  await fetch();
  // Visiting Meus Tickets clears the sidebar unread badge — the operator
  // is effectively acknowledging every recent notification.
  store.dispatch('tickets/markSeen');
});

// The user is still on the page but a websocket update just arrived: keep
// the badge quiet as long as they're looking at the list.
const clearUnread = () => store.dispatch('tickets/markSeen');
onUnmounted(clearUnread);
</script>

<template>
  <div class="flex flex-col flex-1 h-full min-w-0 bg-n-background">
    <header
      class="flex items-center justify-between px-6 pt-6 pb-4 border-b border-n-weak"
    >
      <div>
        <h1 class="text-lg font-semibold text-n-slate-12">
          {{ t('MEUS_TICKETS.TITLE') }}
        </h1>
        <p class="text-sm text-n-slate-11">
          {{ t('MEUS_TICKETS.SUBTITLE') }}
        </p>
      </div>
      <div class="flex items-center gap-4">
        <label class="inline-flex items-center gap-2 text-sm text-n-slate-12">
          <input
            v-model="hideFinished"
            type="checkbox"
            class="size-4 rounded border-n-weak"
          />
          {{ t('MEUS_TICKETS.FILTERS.HIDE_FINISHED') }}
        </label>
        <div class="flex items-center gap-2">
          <span class="text-sm text-n-slate-11">
            {{ t('MEUS_TICKETS.FILTERS.STATUS') }}
          </span>
          <Select v-model="statusFilter" :options="statusFilterOptions" />
        </div>
      </div>
    </header>

    <div class="flex-1 overflow-y-auto px-6 py-4">
      <div v-if="uiFlags.fetchingList" class="flex justify-center py-12">
        <Spinner class="text-n-brand" />
      </div>
      <BaseTable
        v-else
        :headers="tableHeaders"
        :items="records"
        :no-data-message="t('MEUS_TICKETS.EMPTY')"
      >
        <template #row="{ items }">
          <BaseTableRow
            v-for="ticket in items"
            :key="ticket.id"
            :item="ticket"
            class="cursor-pointer hover:bg-n-solid-2 transition-colors"
            @click="openTicket(ticket)"
          >
            <template #default>
              <BaseTableCell>
                <span
                  class="text-body-main font-medium text-n-slate-12 whitespace-nowrap"
                >
                  {{ ticket.display_id }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-11 whitespace-nowrap">
                  {{ formatDate(ticket.created_at) }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <p class="text-body-main text-n-slate-12 line-clamp-2 max-w-md">
                  {{ ticket.relatar_problema }}
                </p>
              </BaseTableCell>
              <BaseTableCell>
                <span
                  class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium whitespace-nowrap"
                  :class="statusBadgeClass(ticket.clickup_status_name)"
                >
                  {{
                    ticket.clickup_status_name ||
                    t('MEUS_TICKETS.STATUS.PENDING_SYNC')
                  }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <p
                  v-if="ticket.resposta_para_cliente"
                  class="text-body-main text-n-slate-11 line-clamp-2 max-w-md"
                >
                  {{ ticket.resposta_para_cliente }}
                </p>
                <span v-else class="text-n-slate-10">{{ EMPTY_CELL }}</span>
              </BaseTableCell>
              <BaseTableCell v-if="isAdminOrManager">
                <span class="text-body-main text-n-slate-11 whitespace-nowrap">
                  {{ ticket.user?.name || EMPTY_CELL }}
                </span>
              </BaseTableCell>
              <BaseTableCell v-if="isAdministrator">
                <Button
                  v-if="clickupTaskUrl(ticket)"
                  v-tooltip.top="ticket.clickup_task_id"
                  type="button"
                  variant="faded"
                  color="slate"
                  size="xs"
                  icon="i-lucide-external-link"
                  :label="ticket.clickup_task_id"
                  @click="
                    event => openClickupTask(event, clickupTaskUrl(ticket))
                  "
                />
                <span v-else class="text-n-slate-10">{{ EMPTY_CELL }}</span>
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>

      <PaginationFooter
        v-if="records.length > 0"
        class="mt-4"
        :current-page="meta.currentPage"
        :total-items="meta.totalCount"
        :items-per-page="meta.perPage"
        @update:current-page="onPageChange"
      />
    </div>

    <TicketDetailDialog ref="detailDialogRef" />
  </div>
</template>
