<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRoute } from 'vue-router';
import { getUnixStartOfDay, getUnixEndOfDay } from 'helpers/DateHelper';
import { DATE_RANGE_TYPES } from 'dashboard/components/ui/DatePicker/helpers/DatePickerHelper';
import WootDatePicker from 'dashboard/components/ui/DatePicker/DatePicker.vue';
import ReportHeader from './components/ReportHeader.vue';
import IaHumanDistributionReportsAPI from 'dashboard/api/iaHumanDistributionReports';
import Modal from 'dashboard/components/Modal.vue';

const store = useStore();
const route = useRoute();

const inboxes = computed(() => store.getters['inboxes/getInboxes']);

const today = new Date();
const customDateRange = ref([today, today]);
const selectedDateRange = ref(DATE_RANGE_TYPES.CUSTOM_RANGE);
const inboxId = ref('');

const rows = ref([]);
const totals = ref({
  total: 0,
  assigned_via_team: 0,
  assigned_via_team_offline: 0,
  failed_with_online: 0,
  failed_no_online: 0,
});
const loading = ref(false);
const error = ref(null);
const hasFetched = ref(false);

const accountId = computed(() => route.params.accountId);

const conversationUrl = row =>
  `/app/accounts/${accountId.value}/conversations/${row.conversation_id}`;

const fromUnix = computed(() => getUnixStartOfDay(customDateRange.value[0]));
const toUnix = computed(() => getUnixEndOfDay(customDateRange.value[1]));

const fetchData = async () => {
  loading.value = true;
  error.value = null;
  try {
    const { data } = await IaHumanDistributionReportsAPI.fetch({
      from: fromUnix.value,
      to: toUnix.value,
      inboxId: inboxId.value,
    });
    rows.value = data.rows || [];
    totals.value = data.totals || totals.value;
    hasFetched.value = true;
  } catch (e) {
    error.value =
      e.response?.data?.error || e.response?.statusText || e.message;
  } finally {
    loading.value = false;
  }
};

const onDateRangeChange = value => {
  const [startDate, endDate, rangeType] = value;
  customDateRange.value = [startDate, endDate];
  selectedDateRange.value = rangeType || DATE_RANGE_TYPES.CUSTOM_RANGE;
  fetchData();
};

const onInboxChange = () => fetchData();

onMounted(() => {
  store.dispatch('inboxes/get');
  fetchData();
});

const statusPillClass = tag => {
  switch (tag) {
    case 'assigned_via_team':
      return 'bg-n-teal-3 text-n-teal-12';
    case 'assigned_via_team_offline':
      return 'bg-n-amber-3 text-n-amber-12';
    case 'failed_with_online':
      return 'bg-n-amber-3 text-n-amber-12';
    case 'failed_no_online':
      return 'bg-n-ruby-3 text-n-ruby-12';
    default:
      return 'bg-n-alpha-2 text-n-slate-11';
  }
};

const statusIcon = tag => {
  switch (tag) {
    case 'assigned_via_team':
      return '✅';
    case 'assigned_via_team_offline':
      return '🟧';
    case 'failed_with_online':
      return '⚠️';
    case 'failed_no_online':
      return '🔴';
    default:
      return '•';
  }
};

const pct = n => {
  if (!totals.value.total) return '0%';
  return `${Math.round((n / totals.value.total) * 100)}%`;
};

const ONLINE_VISIBLE_LIMIT = 3;

const visibleOnlineMembers = row =>
  (row.online_team_members || []).slice(0, ONLINE_VISIBLE_LIMIT);

const hasMoreOnline = row =>
  (row.online_team_members?.length || 0) > ONLINE_VISIBLE_LIMIT;

const onlineModalOpen = ref(false);
const onlineModalRow = ref(null);

const openOnlineModal = row => {
  onlineModalRow.value = row;
  onlineModalOpen.value = true;
};

const closeOnlineModal = () => {
  onlineModalOpen.value = false;
  onlineModalRow.value = null;
};
</script>

<template>
  <ReportHeader
    :header-title="$t('IA_HUMAN_DISTRIBUTION_REPORT.HEADER')"
    :header-description="$t('IA_HUMAN_DISTRIBUTION_REPORT.DESCRIPTION')"
  />

  <div class="flex flex-col w-full gap-3 lg:flex-row mb-4">
    <select
      v-model="inboxId"
      class="bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg pl-3 pr-9 py-2 text-sm text-n-slate-12 focus:outline-n-brand lg:w-64"
      @change="onInboxChange"
    >
      <option value="">
        {{ $t('IA_HUMAN_DISTRIBUTION_REPORT.ALL_INBOXES') }}
      </option>
      <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
        {{ inbox.name }}
      </option>
    </select>

    <WootDatePicker
      v-model:date-range="customDateRange"
      v-model:range-type="selectedDateRange"
      @date-range-changed="onDateRangeChange"
    />
  </div>

  <div
    v-if="error"
    class="px-4 py-3 mb-4 rounded-lg bg-n-ruby-3 text-n-ruby-12 text-sm"
  >
    {{ $t('IA_HUMAN_DISTRIBUTION_REPORT.ERROR_LOAD', { error }) }}
  </div>

  <div v-if="hasFetched" class="grid grid-cols-2 md:grid-cols-5 gap-3 mb-6">
    <div
      class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-4 py-3"
    >
      <div class="text-xs text-n-slate-11">
        {{ $t('IA_HUMAN_DISTRIBUTION_REPORT.KPI.TOTAL') }}
      </div>
      <div class="text-2xl font-medium text-n-slate-12 mt-1">
        {{ totals.total }}
      </div>
    </div>
    <div
      class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-4 py-3"
    >
      <div class="text-xs text-n-slate-11">
        {{ $t('IA_HUMAN_DISTRIBUTION_REPORT.KPI.VIA_TEAM') }}
      </div>
      <div class="text-2xl font-medium text-n-teal-11 mt-1">
        {{ totals.assigned_via_team }}
        <span class="text-xs text-n-slate-11 ml-1">{{
          pct(totals.assigned_via_team)
        }}</span>
      </div>
    </div>
    <div
      class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-4 py-3"
    >
      <div class="text-xs text-n-slate-11">
        {{ $t('IA_HUMAN_DISTRIBUTION_REPORT.KPI.VIA_TEAM_OFFLINE') }}
      </div>
      <div class="text-2xl font-medium text-n-amber-11 mt-1">
        {{ totals.assigned_via_team_offline }}
        <span class="text-xs text-n-slate-11 ml-1">{{
          pct(totals.assigned_via_team_offline)
        }}</span>
      </div>
    </div>
    <div
      class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-4 py-3"
    >
      <div class="text-xs text-n-slate-11">
        {{ $t('IA_HUMAN_DISTRIBUTION_REPORT.KPI.FAILED') }}
      </div>
      <div class="text-2xl font-medium text-n-amber-11 mt-1">
        {{ totals.failed_with_online }}
        <span class="text-xs text-n-slate-11 ml-1">{{
          pct(totals.failed_with_online)
        }}</span>
      </div>
    </div>
    <div
      class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-4 py-3"
    >
      <div class="text-xs text-n-slate-11">
        {{ $t('IA_HUMAN_DISTRIBUTION_REPORT.KPI.FAILED_NO_ONLINE') }}
      </div>
      <div class="text-2xl font-medium text-n-ruby-11 mt-1">
        {{ totals.failed_no_online }}
        <span class="text-xs text-n-slate-11 ml-1">{{
          pct(totals.failed_no_online)
        }}</span>
      </div>
    </div>
  </div>

  <div
    v-if="hasFetched"
    class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow overflow-x-auto"
  >
    <table class="w-full text-sm">
      <thead class="bg-n-slate-1 text-n-slate-12">
        <tr>
          <th class="text-left px-5 py-3 font-medium text-sm whitespace-nowrap">
            {{ $t('IA_HUMAN_DISTRIBUTION_REPORT.COLUMNS.DATETIME') }}
          </th>
          <th class="text-left px-5 py-3 font-medium text-sm">
            {{ $t('IA_HUMAN_DISTRIBUTION_REPORT.COLUMNS.CONVERSATION') }}
          </th>
          <th class="text-left px-5 py-3 font-medium text-sm whitespace-nowrap">
            {{ $t('IA_HUMAN_DISTRIBUTION_REPORT.COLUMNS.INBOX') }}
          </th>
          <th class="text-left px-5 py-3 font-medium text-sm whitespace-nowrap">
            {{ $t('IA_HUMAN_DISTRIBUTION_REPORT.COLUMNS.TEAM') }}
          </th>
          <th class="text-left px-5 py-3 font-medium text-sm whitespace-nowrap">
            {{ $t('IA_HUMAN_DISTRIBUTION_REPORT.COLUMNS.AGENT') }}
          </th>
          <th class="text-left px-5 py-3 font-medium text-sm">
            {{ $t('IA_HUMAN_DISTRIBUTION_REPORT.COLUMNS.ONLINE_TEAM_MEMBERS') }}
          </th>
          <th class="text-left px-5 py-3 font-medium text-sm whitespace-nowrap">
            {{ $t('IA_HUMAN_DISTRIBUTION_REPORT.COLUMNS.STATUS') }}
          </th>
        </tr>
      </thead>
      <tbody class="divide-y divide-n-slate-2">
        <tr
          v-for="row in rows"
          :key="`${row.timestamp}-${row.conversation_id}`"
          class="text-n-slate-12 hover:bg-n-alpha-1 align-top"
        >
          <td class="px-5 py-3 whitespace-nowrap">
            {{ row.date_label }} {{ row.time_label }}
          </td>
          <td class="px-5 py-3 whitespace-nowrap">
            <a
              :href="conversationUrl(row)"
              target="_blank"
              rel="noopener noreferrer"
              class="text-n-brand hover:underline font-mono"
            >
              {{
                $t('IA_HUMAN_DISTRIBUTION_REPORT.HASH_ID', {
                  id: row.conversation_id,
                })
              }}
            </a>
          </td>
          <td class="px-5 py-3 whitespace-nowrap">
            {{ row.inbox_name || $t('IA_HUMAN_DISTRIBUTION_REPORT.DASH') }}
          </td>
          <td class="px-5 py-3 whitespace-nowrap">
            <span v-if="row.team_name" class="text-n-slate-12">
              {{ row.team_name }}
            </span>
            <span v-else class="text-n-slate-10">
              {{ $t('IA_HUMAN_DISTRIBUTION_REPORT.DASH') }}
            </span>
          </td>
          <td class="px-5 py-3 whitespace-nowrap">
            <span v-if="row.agent_name" class="text-n-slate-12">
              {{ row.agent_name }}
            </span>
            <span v-else class="text-n-slate-10">
              {{ $t('IA_HUMAN_DISTRIBUTION_REPORT.DASH') }}
            </span>
          </td>
          <td class="px-5 py-3 text-xs text-n-slate-11 whitespace-nowrap">
            <template v-if="row.online_team_members?.length">
              <div
                v-for="(member, idx) in visibleOnlineMembers(row)"
                :key="member.id"
              >
                {{ member.name }}
                <button
                  v-if="
                    idx === visibleOnlineMembers(row).length - 1 &&
                    hasMoreOnline(row)
                  "
                  type="button"
                  class="text-n-brand hover:underline focus:outline-none ml-1"
                  @click="openOnlineModal(row)"
                >
                  {{ $t('IA_HUMAN_DISTRIBUTION_REPORT.MORE_DOTS') }}
                </button>
              </div>
            </template>
            <template v-else>
              {{ $t('IA_HUMAN_DISTRIBUTION_REPORT.DASH') }}
            </template>
          </td>
          <td class="px-5 py-3 whitespace-nowrap">
            <span
              class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs"
              :class="statusPillClass(row.status_tag)"
            >
              {{ statusIcon(row.status_tag) }} {{ row.status_text }}
            </span>
          </td>
        </tr>
        <tr v-if="!rows.length && !loading">
          <td colspan="7" class="px-5 py-8 text-center text-n-slate-11">
            {{ $t('IA_HUMAN_DISTRIBUTION_REPORT.EMPTY_STATE') }}
          </td>
        </tr>
        <tr v-if="loading">
          <td colspan="7" class="px-5 py-8 text-center text-n-slate-11">
            {{ $t('IA_HUMAN_DISTRIBUTION_REPORT.LOADING') }}
          </td>
        </tr>
      </tbody>
    </table>
    <div class="px-5 py-3 text-xs text-n-slate-11 border-t border-n-slate-2">
      {{ $t('IA_HUMAN_DISTRIBUTION_REPORT.ROW_COUNT', { count: rows.length }) }}
    </div>
  </div>

  <Modal v-model:show="onlineModalOpen" :on-close="closeOnlineModal">
    <div class="flex flex-col h-auto overflow-auto">
      <woot-modal-header
        :header-title="
          $t('IA_HUMAN_DISTRIBUTION_REPORT.ONLINE_LIST_HEADER', {
            count: onlineModalRow?.online_team_members?.length || 0,
          })
        "
      />
      <ul class="px-8 py-4 space-y-2 text-sm text-n-slate-12">
        <li
          v-for="member in onlineModalRow?.online_team_members || []"
          :key="member.id"
        >
          {{ member.name }}
        </li>
      </ul>
    </div>
  </Modal>
</template>
