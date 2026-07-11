<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TicketDetailDialog from 'dashboard/components-next/feedback/TicketDetailDialog.vue';

// Meus Tickets. Renders every ticket the current user is allowed to see —
// TicketPolicy::Scope on the backend already trims the payload to "own for
// agent, everything for manager/admin", so this component doesn't need to
// duplicate that check; it only decides whether to show the "Agente" column.

const { t } = useI18n();
const store = useStore();

const records = useMapGetter('tickets/getRecords');
const meta = useMapGetter('tickets/getMeta');
const uiFlags = useMapGetter('tickets/getUIFlags');
const currentRole = useMapGetter('getCurrentRole');

const isAdminOrManager = computed(() =>
  ['administrator', 'manager'].includes(currentRole.value)
);

const statusFilter = ref('');
const currentPage = ref(1);
const detailDialogRef = ref(null);
const EMPTY_CELL = '—';

const fetch = async () => {
  await store.dispatch('tickets/fetchAll', {
    page: currentPage.value,
    status: statusFilter.value || undefined,
  });
};

const openTicket = ticket => {
  detailDialogRef.value?.openWith(ticket);
};

watch(statusFilter, () => {
  currentPage.value = 1;
  fetch();
});

const nextPage = () => {
  currentPage.value += 1;
  fetch();
};

const prevPage = () => {
  if (currentPage.value <= 1) return;
  currentPage.value -= 1;
  fetch();
};

const hasNextPage = computed(() => {
  const { totalCount, currentPage: page, perPage } = meta.value;
  return page * perPage < totalCount;
});

const statusBadgeClass = statusName => {
  const slug = (statusName || '').toLowerCase();
  if (['resolvido'].includes(slug)) return 'bg-n-teal-3 text-n-teal-11';
  if (['restrição', 'restricao'].includes(slug))
    return 'bg-n-amber-3 text-n-amber-11';
  if (['encerrado'].includes(slug)) return 'bg-n-slate-3 text-n-slate-11';
  if (['em análise', 'em analise'].includes(slug))
    return 'bg-n-sky-3 text-n-sky-11';
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
      <div class="flex items-center gap-3">
        <label class="text-xs text-n-slate-11">
          {{ t('MEUS_TICKETS.FILTERS.STATUS') }}
        </label>
        <select
          v-model="statusFilter"
          class="text-sm rounded-lg border border-n-slate-6 bg-n-solid-2 px-3 py-1.5 text-n-slate-12 focus:outline-none focus:border-n-brand"
        >
          <option value="">{{ t('MEUS_TICKETS.FILTERS.ALL') }}</option>
          <option value="aberto">
            {{ t('MEUS_TICKETS.STATUS.ABERTO') }}
          </option>
          <option value="em análise">
            {{ t('MEUS_TICKETS.STATUS.EM_ANALISE') }}
          </option>
          <option value="resolvido">
            {{ t('MEUS_TICKETS.STATUS.RESOLVIDO') }}
          </option>
          <option value="restrição">
            {{ t('MEUS_TICKETS.STATUS.RESTRICAO') }}
          </option>
          <option value="encerrado">
            {{ t('MEUS_TICKETS.STATUS.ENCERRADO') }}
          </option>
        </select>
      </div>
    </header>

    <div class="flex-1 overflow-y-auto px-6 py-4">
      <div v-if="uiFlags.fetchingList" class="flex justify-center py-12">
        <Spinner class="text-n-brand" />
      </div>
      <div
        v-else-if="records.length === 0"
        class="flex flex-col items-center justify-center py-16 text-center text-n-slate-11"
      >
        <i class="i-lucide-flag size-10 mb-3" />
        <p class="text-sm">
          {{ t('MEUS_TICKETS.EMPTY') }}
        </p>
      </div>
      <div v-else class="rounded-xl border border-n-weak overflow-hidden">
        <table class="w-full text-sm">
          <thead
            class="bg-n-solid-2 text-xs uppercase text-n-slate-11 tracking-wide"
          >
            <tr>
              <th class="px-4 py-3 text-left">
                {{ t('MEUS_TICKETS.COLUMNS.OPENED_AT') }}
              </th>
              <th class="px-4 py-3 text-left">
                {{ t('MEUS_TICKETS.COLUMNS.PROBLEM') }}
              </th>
              <th class="px-4 py-3 text-left">
                {{ t('MEUS_TICKETS.COLUMNS.STATUS') }}
              </th>
              <th class="px-4 py-3 text-left">
                {{ t('MEUS_TICKETS.COLUMNS.RESPONSE') }}
              </th>
              <th v-if="isAdminOrManager" class="px-4 py-3 text-left">
                {{ t('MEUS_TICKETS.COLUMNS.AGENT') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="ticket in records"
              :key="ticket.id"
              class="border-t border-n-weak hover:bg-n-solid-2 cursor-pointer transition-colors"
              @click="openTicket(ticket)"
            >
              <td class="px-4 py-3 text-n-slate-11 whitespace-nowrap">
                {{ formatDate(ticket.created_at) }}
              </td>
              <td class="px-4 py-3 text-n-slate-12 max-w-md">
                <p class="line-clamp-2">
                  {{ ticket.relatar_problema }}
                </p>
              </td>
              <td class="px-4 py-3">
                <span
                  class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium"
                  :class="statusBadgeClass(ticket.clickup_status_name)"
                >
                  {{
                    ticket.clickup_status_name ||
                    t('MEUS_TICKETS.STATUS.PENDING_SYNC')
                  }}
                </span>
              </td>
              <td class="px-4 py-3 text-n-slate-11 max-w-md">
                <p v-if="ticket.resposta_para_cliente" class="line-clamp-2">
                  {{ ticket.resposta_para_cliente }}
                </p>
                <span v-else class="text-n-slate-10">{{ EMPTY_CELL }}</span>
              </td>
              <td v-if="isAdminOrManager" class="px-4 py-3 text-n-slate-11">
                {{ ticket.user?.name || EMPTY_CELL }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div
        v-if="records.length > 0"
        class="flex items-center justify-between mt-4 text-xs text-n-slate-11"
      >
        <span>
          {{
            t('MEUS_TICKETS.PAGINATION.SUMMARY', {
              from: (meta.currentPage - 1) * meta.perPage + 1,
              to: Math.min(meta.currentPage * meta.perPage, meta.totalCount),
              total: meta.totalCount,
            })
          }}
        </span>
        <div class="flex gap-2">
          <button
            type="button"
            class="px-3 py-1 rounded-md border border-n-weak disabled:opacity-40 hover:bg-n-solid-2"
            :disabled="currentPage <= 1"
            @click="prevPage"
          >
            {{ t('MEUS_TICKETS.PAGINATION.PREV') }}
          </button>
          <button
            type="button"
            class="px-3 py-1 rounded-md border border-n-weak disabled:opacity-40 hover:bg-n-solid-2"
            :disabled="!hasNextPage"
            @click="nextPage"
          >
            {{ t('MEUS_TICKETS.PAGINATION.NEXT') }}
          </button>
        </div>
      </div>
    </div>

    <TicketDetailDialog ref="detailDialogRef" />
  </div>
</template>
