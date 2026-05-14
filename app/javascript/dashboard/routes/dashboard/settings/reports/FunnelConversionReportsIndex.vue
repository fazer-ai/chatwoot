<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import subDays from 'date-fns/subDays';

import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import WootDatePicker from 'dashboard/components/ui/DatePicker/DatePicker.vue';
import { DATE_RANGE_TYPES } from 'dashboard/components/ui/DatePicker/helpers/DatePickerHelper';
import { getUnixStartOfDay, getUnixEndOfDay } from 'helpers/DateHelper';
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
const report = useMapGetter('summaryReports/getFunnelConversionReport');
const isLoading = computed(
  () => uiFlags.value.isFetchingFunnelConversionReports ?? false
);

const stages = computed(() => report.value?.stages || []);
const kpis = computed(() => report.value?.kpis || {});

// Max count across all stages drives the bar width. If all zero we keep the
// scale at 1 to avoid dividing by zero (bars render as 0% width either way).
const maxCount = computed(() => {
  const counts = stages.value.map(s => s.count || 0);
  return Math.max(1, ...counts);
});

const barWidthFor = count => {
  const pct = ((count || 0) / maxCount.value) * 100;
  return `${pct}%`;
};

const formatRate = value => {
  if (value === null || value === undefined) return '--';
  return `${Number(value).toFixed(1)}%`;
};

const formatCount = value => {
  if (value === null || value === undefined) return '--';
  return Number(value).toLocaleString();
};

const fetchReports = async () => {
  const params = { since: from.value, until: to.value };
  try {
    await store.dispatch('summaryReports/fetchFunnelConversionReports', params);
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
</script>

<template>
  <ReportHeader
    :header-title="$t('FUNNEL_CONVERSION_REPORTS.HEADER')"
    :header-description="$t('FUNNEL_CONVERSION_REPORTS.DESCRIPTION')"
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

  <!-- KPI strip -->
  <div class="grid grid-cols-1 gap-3 mt-5 sm:grid-cols-3">
    <div
      class="px-5 py-4 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
    >
      <div class="text-sm text-n-slate-11 whitespace-nowrap">
        {{ $t('FUNNEL_CONVERSION_REPORTS.KPIS.TOP_COUNT') }}
      </div>
      <div class="mt-2 text-3xl font-semibold text-n-slate-12">
        {{ formatCount(kpis.topCount) }}
      </div>
    </div>
    <div
      class="px-5 py-4 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
    >
      <div class="text-sm text-n-slate-11 whitespace-nowrap">
        {{ $t('FUNNEL_CONVERSION_REPORTS.KPIS.COMPLETED') }}
      </div>
      <div class="mt-2 text-3xl font-semibold text-n-slate-12">
        {{ formatCount(kpis.completedCount) }}
      </div>
    </div>
    <div
      class="px-5 py-4 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
    >
      <div class="text-sm text-n-slate-11 whitespace-nowrap">
        {{ $t('FUNNEL_CONVERSION_REPORTS.KPIS.WIN_RATE') }}
      </div>
      <div class="mt-2 text-3xl font-semibold text-n-slate-12">
        {{ formatRate(kpis.winRate) }}
      </div>
      <div class="text-xs text-n-slate-11 mt-1 whitespace-nowrap">
        {{
          $t('FUNNEL_CONVERSION_REPORTS.WIN_RATE_DETAIL', {
            won: formatCount(kpis.wonCount),
            total: formatCount(kpis.completedCount),
          })
        }}
      </div>
    </div>
  </div>

  <!-- Funnel chart -->
  <div
    class="relative px-6 py-5 mt-5 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
  >
    <div
      v-if="!isLoading && stages.length === 0"
      class="py-10 text-center text-n-slate-11"
    >
      {{ $t('FUNNEL_CONVERSION_REPORTS.EMPTY_STATE') }}
    </div>

    <div v-else class="flex flex-col gap-2">
      <template v-for="stage in stages" :key="stage.id">
        <div class="flex flex-col gap-2">
          <!-- Stage header -->
          <div class="flex items-center gap-3">
            <span
              class="w-2.5 h-2.5 rounded-full flex-shrink-0"
              :style="{ backgroundColor: stage.color || '#94a3b8' }"
            />
            <span class="text-sm font-medium text-n-slate-12 whitespace-nowrap">
              {{ stage.name }}
            </span>
            <span class="ml-auto text-lg font-semibold text-n-slate-12">
              {{ formatCount(stage.count) }}
            </span>
          </div>

          <!-- Proportional bar -->
          <div
            class="relative h-6 w-full rounded-md bg-n-alpha-1 overflow-hidden"
          >
            <div
              class="h-full rounded-md transition-all duration-300 opacity-90"
              :style="{
                width: barWidthFor(stage.count),
                backgroundColor: stage.color || '#94a3b8',
              }"
            />
          </div>
        </div>

        <!-- Conversion arrow to next stage -->
        <div
          v-if="
            stage.conversionRate !== null && stage.conversionRate !== undefined
          "
          class="flex items-center gap-2 pl-5 my-1 text-xs text-n-slate-11 whitespace-nowrap"
        >
          <span class="i-lucide-arrow-down text-n-slate-10" />
          <span class="text-n-slate-12 font-medium">
            {{
              $t('FUNNEL_CONVERSION_REPORTS.CONVERSION_VALUE', {
                rate: formatRate(stage.conversionRate),
              })
            }}
          </span>
          <span class="text-n-slate-10">
            {{ $t('FUNNEL_CONVERSION_REPORTS.SEPARATOR') }}
          </span>
          <span>
            {{
              $t('FUNNEL_CONVERSION_REPORTS.DROP_OFF_LABEL', {
                count: formatCount(stage.dropOffCount),
              })
            }}
          </span>
          <span
            v-if="stage.conversionExceedsPrevious"
            class="ml-1 i-lucide-info text-n-amber-11"
            :title="$t('FUNNEL_CONVERSION_REPORTS.EXCEEDS_TOOLTIP')"
          />
        </div>
      </template>
    </div>

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
        class="absolute inset-0 flex justify-center pt-[6rem] bg-n-solid-1/70 rounded-xl pointer-events-none"
      >
        <Spinner :size="32" class="text-n-brand" />
      </div>
    </Transition>
  </div>
</template>
