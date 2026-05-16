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
import LossReasonsDonut from './LossReasonsDonut.vue';

const store = useStore();
const { t } = useI18n();

const customDateRange = ref([subDays(new Date(), 6), new Date()]);
const selectedDateRange = ref(DATE_RANGE_TYPES.LAST_7_DAYS);
const from = ref(getUnixStartOfDay(customDateRange.value[0]));
const to = ref(getUnixEndOfDay(customDateRange.value[1]));
const inboxId = ref('');
const labelName = ref('');

const uiFlags = useMapGetter('summaryReports/getUIFlags');
const report = useMapGetter('summaryReports/getFunnelConversionReport');
const inboxes = useMapGetter('inboxes/getInboxes');
const labels = useMapGetter('labels/getLabels');
const isLoading = computed(
  () => uiFlags.value.isFetchingFunnelConversionReports ?? false
);

const stages = computed(() => report.value?.stages || []);
const kpis = computed(() => report.value?.kpis || {});
const lossReasons = computed(() => report.value?.lossReasons || []);

const inboxOptions = computed(() =>
  [...inboxes.value].sort((a, b) => a.name.localeCompare(b.name))
);

const labelOptions = computed(() =>
  [...labels.value].sort((a, b) => a.title.localeCompare(b.title))
);

const formatRate = value => {
  if (value === null || value === undefined) return '--';
  return `${Number(value).toFixed(1)}%`;
};

const fetchReports = async () => {
  const params = {
    since: from.value,
    until: to.value,
    inboxId: inboxId.value || undefined,
    label: labelName.value || undefined,
  };
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

const onInboxChange = event => {
  inboxId.value = event.target.value;
  fetchReports();
};

const onLabelChange = event => {
  labelName.value = event.target.value;
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
              {{ $t('FUNNEL_CONVERSION_REPORTS.FILTERS.INBOX_ANY') }}
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
              {{ $t('FUNNEL_CONVERSION_REPORTS.FILTERS.LABEL_ANY') }}
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

    <!-- KPI strip mirrors the chart row below: the three funnel-flow rates
         (scheduling / confirmation / attendance) sit over the funnel chart
         column (col-span-2 with a nested 3-col grid), while the no-show rate
         sits over the loss-reasons donut column. Layout stacks below md. -->
    <div class="grid grid-cols-1 gap-3 mt-2 md:grid-cols-3">
      <div class="md:col-span-2 grid grid-cols-1 gap-3 sm:grid-cols-3">
        <div
          class="px-5 py-4 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
        >
          <div class="text-sm text-n-slate-11 whitespace-nowrap">
            {{ $t('FUNNEL_CONVERSION_REPORTS.KPIS.SCHEDULING_RATE') }}
          </div>
          <div class="mt-2 text-3xl font-semibold text-n-slate-12">
            {{ formatRate(kpis.schedulingRate) }}
          </div>
        </div>
        <div
          class="px-5 py-4 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
        >
          <div class="text-sm text-n-slate-11 whitespace-nowrap">
            {{ $t('FUNNEL_CONVERSION_REPORTS.KPIS.CONFIRMATION_RATE') }}
          </div>
          <div class="mt-2 text-3xl font-semibold text-n-slate-12">
            {{ formatRate(kpis.confirmationRate) }}
          </div>
        </div>
        <div
          class="px-5 py-4 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
        >
          <div class="text-sm text-n-slate-11 whitespace-nowrap">
            {{ $t('FUNNEL_CONVERSION_REPORTS.KPIS.ATTENDANCE_RATE') }}
          </div>
          <div class="mt-2 text-3xl font-semibold text-n-slate-12">
            {{ formatRate(kpis.attendanceRate) }}
          </div>
        </div>
      </div>
      <div
        class="md:col-span-1 px-5 py-4 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
      >
        <div class="text-sm text-n-slate-11 whitespace-nowrap">
          {{ $t('FUNNEL_CONVERSION_REPORTS.KPIS.NO_SHOW_RATE') }}
        </div>
        <div class="mt-2 text-3xl font-semibold text-n-slate-12">
          {{ formatRate(kpis.noShowRate) }}
        </div>
      </div>
    </div>

    <!-- Funnel + loss-reasons row. Funnel needs more horizontal width to be
         readable across many stages, so it takes 2/3 on md+ while the donut
         breakdown sits on the remaining third. Stacks vertically below md. -->
    <div class="relative mt-2 grid grid-cols-1 gap-3 md:grid-cols-3">
      <div
        class="md:col-span-2 px-6 py-5 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
      >
        <div
          v-if="!isLoading && stages.length === 0"
          class="py-10 text-center text-n-slate-11"
        >
          {{ $t('FUNNEL_CONVERSION_REPORTS.EMPTY_STATE') }}
        </div>

        <FunnelChart v-else :stages="stages" />
      </div>

      <div
        class="md:col-span-1 px-6 py-5 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
      >
        <div class="text-sm font-medium text-n-slate-12 mb-4">
          {{ $t('FUNNEL_CONVERSION_REPORTS.LOSS_REASONS.HEADER') }}
        </div>
        <div
          v-if="!isLoading && lossReasons.length === 0"
          class="py-10 text-center text-n-slate-11 text-sm"
        >
          {{ $t('FUNNEL_CONVERSION_REPORTS.LOSS_REASONS.EMPTY_STATE') }}
        </div>
        <LossReasonsDonut v-else :reasons="lossReasons" />
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
  </div>
</template>
