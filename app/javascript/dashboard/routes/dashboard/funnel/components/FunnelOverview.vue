<script setup>
import { computed, h, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
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

const store = useStore();
const { t } = useI18n();

const customDateRange = ref([subDays(new Date(), 6), new Date()]);
const selectedDateRange = ref(DATE_RANGE_TYPES.LAST_7_DAYS);
const from = ref(getUnixStartOfDay(customDateRange.value[0]));
const to = ref(getUnixEndOfDay(customDateRange.value[1]));
const inboxId = ref('');
const labelName = ref('');

const uiFlags = useMapGetter('summaryReports/getUIFlags');
const reportMetrics = useMapGetter('summaryReports/getFunnelSummaryReports');
const inboxes = useMapGetter('inboxes/getInboxes');
const labels = useMapGetter('labels/getLabels');
const isLoading = computed(
  () => uiFlags.value.isFetchingFunnelSummaryReports ?? false
);

const inboxOptions = computed(() =>
  [...inboxes.value].sort((a, b) => a.name.localeCompare(b.name))
);

const labelOptions = computed(() =>
  [...labels.value].sort((a, b) => a.title.localeCompare(b.title))
);

const renderCount = value =>
  typeof value === 'number' ? value.toLocaleString() : '--';
const renderTime = value => (value ? formatTime(value) : '--');

const columnHelper = createColumnHelper();
const nowrapHeader = label => () =>
  h('span', { class: 'whitespace-nowrap' }, label);

const defaultRender = cellProps =>
  h(
    'span',
    {
      class: [
        'whitespace-nowrap',
        cellProps.getValue() ? '' : 'text-n-slate-12',
      ],
    },
    cellProps.getValue()
  );

const renderStageName = cellProps => {
  const row = cellProps.row.original;
  return h('div', { class: 'flex items-center gap-2 whitespace-nowrap' }, [
    h('span', {
      class: 'w-2.5 h-2.5 rounded-full flex-shrink-0',
      style: { backgroundColor: row.color || '#94a3b8' },
    }),
    h('span', { class: 'text-n-slate-12' }, row.name),
  ]);
};

const columns = computed(() => [
  columnHelper.accessor('name', {
    header: nowrapHeader(t('FUNNEL_REPORTS.COLUMNS.STAGE')),
    width: 260,
    cell: renderStageName,
  }),
  columnHelper.accessor('enteredCount', {
    header: nowrapHeader(t('FUNNEL_REPORTS.COLUMNS.ENTERED')),
    width: 200,
    cell: defaultRender,
  }),
  columnHelper.accessor('inStageCount', {
    header: nowrapHeader(t('FUNNEL_REPORTS.COLUMNS.IN_STAGE')),
    width: 200,
    cell: defaultRender,
  }),
  columnHelper.accessor('avgTimeInStage', {
    header: nowrapHeader(t('FUNNEL_REPORTS.COLUMNS.AVG_TIME')),
    width: 220,
    cell: defaultRender,
  }),
  columnHelper.accessor('wonCount', {
    header: nowrapHeader(t('FUNNEL_REPORTS.COLUMNS.WON')),
    width: 140,
    cell: defaultRender,
  }),
  columnHelper.accessor('lostCount', {
    header: nowrapHeader(t('FUNNEL_REPORTS.COLUMNS.LOST')),
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
    wonCount: row.closed ? '--' : renderCount(row.wonCount),
    lostCount: row.closed ? '--' : renderCount(row.lostCount),
  }))
);

const fetchReports = async () => {
  const params = {
    since: from.value,
    until: to.value,
    inboxId: inboxId.value || undefined,
    label: labelName.value || undefined,
  };
  try {
    await store.dispatch('summaryReports/fetchFunnelSummaryReports', params);
  } catch {
    useAlert(t('REPORT.SUMMARY_FETCHING_FAILED'));
  }
};

const onInboxChange = event => {
  inboxId.value = event.target.value;
  fetchReports();
};

const onLabelChange = event => {
  labelName.value = event.target.value;
  fetchReports();
};

const onDateRangeChange = value => {
  const [startDate, endDate, rangeType] = value;
  customDateRange.value = [startDate, endDate];
  selectedDateRange.value = rangeType || DATE_RANGE_TYPES.CUSTOM_RANGE;
  from.value = getUnixStartOfDay(startDate);
  to.value = getUnixEndOfDay(endDate);
  fetchReports();
};

onMounted(fetchReports);

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
  <div class="flex flex-col flex-1 gap-3 px-6 py-5 overflow-auto">
    <section class="flex flex-col gap-2 pb-2">
      <span class="text-heading-1 text-n-slate-12">
        {{ $t('FUNNEL_REPORTS.HEADER') }}
      </span>
      <p
        class="text-n-slate-11 mb-0 line-clamp-5 sm:line-clamp-none text-body-main"
      >
        {{ $t('FUNNEL_REPORTS.DESCRIPTION') }}
      </p>
    </section>

    <div
      class="flex flex-col justify-between gap-3 md:flex-row"
      :class="{ 'pointer-events-none opacity-50': isLoading }"
    >
      <div class="flex flex-col flex-wrap items-start gap-3 md:flex-row">
        <WootDatePicker
          v-model:date-range="customDateRange"
          v-model:range-type="selectedDateRange"
          @date-range-changed="onDateRangeChange"
        />
        <div class="relative flex-shrink-0">
          <select
            :value="inboxId"
            class="h-10 text-sm rounded-md border border-n-weak bg-n-input-background px-2 text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-blue-9 w-[10.5rem]"
            @change="onInboxChange"
          >
            <option value="">
              {{ $t('FUNNEL_REPORTS.FILTERS.INBOX_ANY') }}
            </option>
            <option
              v-for="inbox in inboxOptions"
              :key="inbox.id"
              :value="inbox.id"
            >
              {{ inbox.name }}
            </option>
          </select>
        </div>
        <div class="relative flex-shrink-0">
          <select
            :value="labelName"
            class="h-10 text-sm rounded-md border border-n-weak bg-n-input-background px-2 text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-blue-9 w-[10.5rem]"
            @change="onLabelChange"
          >
            <option value="">
              {{ $t('FUNNEL_REPORTS.FILTERS.LABEL_ANY') }}
            </option>
            <option
              v-for="label in labelOptions"
              :key="label.id"
              :value="label.title"
            >
              {{ label.title }}
            </option>
          </select>
        </div>
      </div>
    </div>

    <div
      class="relative flex-1 overflow-auto px-2 py-2 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
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
  </div>
</template>
