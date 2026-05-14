<script setup>
import { computed, h, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { formatTime } from '@chatwoot/utils';
import subDays from 'date-fns/subDays';

import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import {
  useVueTable,
  createColumnHelper,
  getCoreRowModel,
} from '@tanstack/vue-table';

import WootDatePicker from 'dashboard/components/ui/DatePicker/DatePicker.vue';
import { DATE_RANGE_TYPES } from 'dashboard/components/ui/DatePicker/helpers/DatePickerHelper';
import { getUnixStartOfDay, getUnixEndOfDay } from 'helpers/DateHelper';
import Table from 'dashboard/components/table/Table.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

import ReportHeader from './components/ReportHeader.vue';
import {
  generateReportURLParams,
  parseReportURLParams,
} from './helpers/reportFilterHelper';

const store = useStore();
const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const customDateRange = ref([subDays(new Date(), 6), new Date()]);
const selectedDateRange = ref(DATE_RANGE_TYPES.LAST_7_DAYS);
const from = ref(0);
const to = ref(0);

const uiFlags = useMapGetter('summaryReports/getUIFlags');
const reportMetrics = useMapGetter('summaryReports/getFunnelSummaryReports');
const isLoading = computed(
  () => uiFlags.value.isFetchingFunnelSummaryReports ?? false
);

const renderCount = value =>
  typeof value === 'number' ? value.toLocaleString() : '--';
const renderTime = value => (value ? formatTime(value) : '--');

const columnHelper = createColumnHelper();
const defaultRender = cellProps =>
  h(
    'span',
    { class: cellProps.getValue() ? '' : 'text-n-slate-12' },
    cellProps.getValue()
  );

const renderStageName = cellProps => {
  const row = cellProps.row.original;
  return h('div', { class: 'flex items-center gap-2' }, [
    h('span', {
      class: 'w-2.5 h-2.5 rounded-full flex-shrink-0',
      style: { backgroundColor: row.color || '#94a3b8' },
    }),
    h('span', { class: 'text-n-slate-12' }, row.name),
  ]);
};

const columns = computed(() => [
  columnHelper.accessor('name', {
    header: t('FUNNEL_REPORTS.COLUMNS.STAGE'),
    width: 260,
    cell: renderStageName,
  }),
  columnHelper.accessor('inStageCount', {
    header: t('FUNNEL_REPORTS.COLUMNS.IN_STAGE'),
    width: 160,
    cell: defaultRender,
  }),
  columnHelper.accessor('enteredCount', {
    header: t('FUNNEL_REPORTS.COLUMNS.ENTERED'),
    width: 180,
    cell: defaultRender,
  }),
  columnHelper.accessor('avgTimeInStage', {
    header: t('FUNNEL_REPORTS.COLUMNS.AVG_TIME'),
    width: 200,
    cell: defaultRender,
  }),
  columnHelper.accessor('wonCount', {
    header: t('FUNNEL_REPORTS.COLUMNS.WON'),
    width: 140,
    cell: defaultRender,
  }),
  columnHelper.accessor('lostCount', {
    header: t('FUNNEL_REPORTS.COLUMNS.LOST'),
    width: 140,
    cell: defaultRender,
  }),
]);

const tableData = computed(() =>
  (reportMetrics.value || []).map(row => ({
    id: row.id,
    name: row.name,
    color: row.color,
    closed: row.closed,
    inStageCount: renderCount(row.inStageCount),
    enteredCount: renderCount(row.enteredCount),
    avgTimeInStage: renderTime(row.avgTimeInStage),
    // Closed stages don't have downstream exits to "won/lost" — render as --
    // instead of a misleading zero so the table stays honest.
    wonCount: row.closed ? '--' : renderCount(row.wonCount),
    lostCount: row.closed ? '--' : renderCount(row.lostCount),
  }))
);

const fetchReports = async () => {
  const params = { since: from.value, until: to.value };
  try {
    await store.dispatch('summaryReports/fetchFunnelSummaryReports', params);
  } catch {
    useAlert(t('REPORT.SUMMARY_FETCHING_FAILED'));
  }
};

const updateURLParams = () => {
  const params = generateReportURLParams({
    from: from.value,
    to: to.value,
    range: selectedDateRange.value,
  });
  router.replace({ query: { ...params } });
};

const onDateRangeChange = value => {
  const [startDate, endDate, rangeType] = value;
  customDateRange.value = [startDate, endDate];
  selectedDateRange.value = rangeType || DATE_RANGE_TYPES.CUSTOM_RANGE;
  from.value = getUnixStartOfDay(startDate);
  to.value = getUnixEndOfDay(endDate);
  updateURLParams();
  fetchReports();
};

const initializeFromURL = () => {
  const urlParams = parseReportURLParams(route.query);
  if (urlParams.range) selectedDateRange.value = urlParams.range;
  if (urlParams.from && urlParams.to) {
    customDateRange.value = [
      new Date(urlParams.from * 1000),
      new Date(urlParams.to * 1000),
    ];
  }
  from.value = getUnixStartOfDay(customDateRange.value[0]);
  to.value = getUnixEndOfDay(customDateRange.value[1]);
};

onMounted(() => {
  initializeFromURL();
  fetchReports();
});

const table = useVueTable({
  get data() {
    return tableData.value;
  },
  get columns() {
    return columns.value;
  },
  enableSorting: false,
  getCoreRowModel: getCoreRowModel(),
});
</script>

<template>
  <ReportHeader
    :header-title="$t('FUNNEL_REPORTS.HEADER')"
    :header-description="$t('FUNNEL_REPORTS.DESCRIPTION')"
  />

  <div
    class="flex flex-col justify-between gap-3 md:flex-row"
    :class="{ 'pointer-events-none opacity-50': isLoading }"
  >
    <div class="flex flex-col flex-wrap items-start gap-2 md:flex-row">
      <WootDatePicker
        v-model:date-range="customDateRange"
        v-model:range-type="selectedDateRange"
        @date-range-changed="onDateRangeChange"
      />
    </div>
  </div>

  <div
    class="relative flex-1 overflow-auto px-2 py-2 mt-5 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
  >
    <Table :table="table" />
    <Transition
      enter-active-class="transition-opacity duration-300 ease-out"
      leave-active-class="transition-opacity duration-200 ease-in"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div
        v-if="isLoading"
        class="absolute inset-0 flex justify-center pt-[12.5rem] bg-n-solid-1/70 rounded-xl pointer-events-none"
      >
        <Spinner :size="32" class="text-n-brand" />
      </div>
    </Transition>
  </div>
</template>
