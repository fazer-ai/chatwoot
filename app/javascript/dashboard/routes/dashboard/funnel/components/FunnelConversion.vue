<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import subDays from 'date-fns/subDays';

import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import WootDatePicker from 'dashboard/components/ui/DatePicker/DatePicker.vue';
import { DATE_RANGE_TYPES } from 'dashboard/components/ui/DatePicker/helpers/DatePickerHelper';
import { getUnixStartOfDay, getUnixEndOfDay } from 'helpers/DateHelper';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

import FunnelChart from './FunnelChart.vue';

const store = useStore();
const { t } = useI18n();

const customDateRange = ref([subDays(new Date(), 6), new Date()]);
const selectedDateRange = ref(DATE_RANGE_TYPES.LAST_7_DAYS);
const from = ref(getUnixStartOfDay(customDateRange.value[0]));
const to = ref(getUnixEndOfDay(customDateRange.value[1]));

const uiFlags = useMapGetter('summaryReports/getUIFlags');
const report = useMapGetter('summaryReports/getFunnelConversionReport');
const isLoading = computed(
  () => uiFlags.value.isFetchingFunnelConversionReports ?? false
);

const stages = computed(() => report.value?.stages || []);
const kpis = computed(() => report.value?.kpis || {});

const formatCount = value => {
  if (value === null || value === undefined) return '--';
  return Number(value).toLocaleString();
};

const formatRate = value => {
  if (value === null || value === undefined) return '--';
  return `${Number(value).toFixed(1)}%`;
};

const fetchReports = async () => {
  const params = { since: from.value, until: to.value };
  try {
    await store.dispatch('summaryReports/fetchFunnelConversionReports', params);
  } catch {
    useAlert(t('REPORT.SUMMARY_FETCHING_FAILED'));
  }
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
</script>

<template>
  <div class="flex flex-col flex-1 gap-3 px-6 py-5 overflow-auto">
    <section class="flex flex-col gap-2 pb-2">
      <span class="text-heading-1 text-n-slate-12">
        {{ $t('FUNNEL_CONVERSION_REPORTS.HEADER') }}
      </span>
      <p
        class="text-n-slate-11 mb-0 line-clamp-5 sm:line-clamp-none text-body-main"
      >
        {{ $t('FUNNEL_CONVERSION_REPORTS.DESCRIPTION') }}
      </p>
    </section>

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
    <div class="grid grid-cols-1 gap-3 mt-2 sm:grid-cols-3">
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

    <!-- Funnel chart card -->
    <div
      class="relative px-6 py-5 mt-2 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
    >
      <div
        v-if="!isLoading && stages.length === 0"
        class="py-10 text-center text-n-slate-11"
      >
        {{ $t('FUNNEL_CONVERSION_REPORTS.EMPTY_STATE') }}
      </div>

      <FunnelChart v-else :stages="stages" />

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
  </div>
</template>
