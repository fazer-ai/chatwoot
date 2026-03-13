<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import DatePicker from 'vue-datepicker-next';
import {
  SCHEDULE_DAY_OPTIONS,
  SCHEDULE_TIME_PERIODS,
  getDayShortcutOptions,
  getShortcutDate,
  applyTimePeriod,
  isTimePeriodPast,
} from 'dashboard/helper/scheduleDateShortcutHelpers';

const props = defineProps({
  modelValue: {
    type: Date,
    default: null,
  },
  dateTimeError: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const selectedDay = ref(null);
const selectedTimePeriod = ref(null);
const customDateTime = ref(null);
const datePickerOpen = ref(false);

const isCustomMode = computed(
  () => selectedDay.value === SCHEDULE_DAY_OPTIONS.CUSTOM
);

const dayOptions = computed(() => getDayShortcutOptions());

const timePeriodOptions = computed(() => {
  if (!selectedDay.value || isCustomMode.value) return [];
  const targetDate = getShortcutDate(selectedDay.value);
  return [
    {
      key: SCHEDULE_TIME_PERIODS.MORNING,
      labelI18nKey: 'SCHEDULED_MESSAGES.MODAL.SHORTCUTS.TIMES.MORNING',
      hour: '8:00',
      disabled: isTimePeriodPast(targetDate, SCHEDULE_TIME_PERIODS.MORNING),
    },
    {
      key: SCHEDULE_TIME_PERIODS.AFTERNOON,
      labelI18nKey: 'SCHEDULED_MESSAGES.MODAL.SHORTCUTS.TIMES.AFTERNOON',
      hour: '13:00',
      disabled: isTimePeriodPast(targetDate, SCHEDULE_TIME_PERIODS.AFTERNOON),
    },
    {
      key: SCHEDULE_TIME_PERIODS.EVENING,
      labelI18nKey: 'SCHEDULED_MESSAGES.MODAL.SHORTCUTS.TIMES.EVENING',
      hour: '18:00',
      disabled: isTimePeriodPast(targetDate, SCHEDULE_TIME_PERIODS.EVENING),
    },
  ];
});

watch(selectedDay, newDay => {
  if (!newDay || isCustomMode.value) {
    selectedTimePeriod.value = null;
    return;
  }
  const targetDate = getShortcutDate(newDay);
  const firstAvailable = [
    SCHEDULE_TIME_PERIODS.MORNING,
    SCHEDULE_TIME_PERIODS.AFTERNOON,
    SCHEDULE_TIME_PERIODS.EVENING,
  ].find(tp => !isTimePeriodPast(targetDate, tp));
  selectedTimePeriod.value = firstAvailable || null;
});

watch([selectedDay, selectedTimePeriod], ([day, time]) => {
  if (!day || isCustomMode.value) return;
  if (!time) {
    emit('update:modelValue', null);
    return;
  }
  const targetDate = getShortcutDate(day);
  const dateTime = applyTimePeriod(targetDate, time);
  emit('update:modelValue', dateTime);
});

// Reset local state when modelValue is cleared externally (e.g. resetForm)
watch(
  () => props.modelValue,
  newValue => {
    if (!newValue) {
      selectedDay.value = null;
      selectedTimePeriod.value = null;
      customDateTime.value = null;
    }
  }
);

const selectDay = key => {
  selectedDay.value = key;
  if (key === SCHEDULE_DAY_OPTIONS.CUSTOM) {
    customDateTime.value = props.modelValue;
  }
};

const selectTimePeriod = option => {
  if (option.disabled) return;
  selectedTimePeriod.value = option.key;
};

const onCustomDateTimeChange = value => {
  customDateTime.value = value;
  emit('update:modelValue', value);
};

const datePickerLang = {
  days: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
  months: [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ],
  yearFormat: 'YYYY',
  monthFormat: 'MMMM',
};

const disablePastDates = date => {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return date < today;
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex flex-col gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('SCHEDULED_MESSAGES.MODAL.SHORTCUTS.DAYS_LABEL') }}
      </span>
      <div class="flex flex-wrap gap-2">
        <button
          v-for="option in dayOptions"
          :key="option.key"
          class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm border-0 transition-colors duration-150 cursor-pointer"
          :class="[
            selectedDay === option.key
              ? 'bg-n-brand/10 text-n-blue-11 font-medium'
              : 'bg-n-alpha-1 dark:bg-n-solid-1 text-n-slate-12 hover:bg-n-alpha-2 dark:hover:bg-n-solid-3',
          ]"
          @click="selectDay(option.key)"
        >
          <span>{{ t(option.labelI18nKey) }}</span>
          <span v-if="option.formattedDate" class="text-n-slate-11">
            {{ option.formattedDate }}
          </span>
        </button>
      </div>
    </div>

    <div v-if="selectedDay && !isCustomMode" class="flex flex-col gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('SCHEDULED_MESSAGES.MODAL.SHORTCUTS.TIMES_LABEL') }}
      </span>
      <div class="flex flex-wrap gap-2">
        <button
          v-for="option in timePeriodOptions"
          :key="option.key"
          :disabled="option.disabled"
          class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm border-0 transition-colors duration-150"
          :class="[
            option.disabled
              ? 'opacity-40 cursor-not-allowed bg-n-alpha-1 dark:bg-n-solid-1 text-n-slate-10'
              : selectedTimePeriod === option.key
                ? 'bg-n-brand/10 text-n-blue-11 font-medium cursor-pointer'
                : 'bg-n-alpha-1 dark:bg-n-solid-1 text-n-slate-12 hover:bg-n-alpha-2 dark:hover:bg-n-solid-3 cursor-pointer',
          ]"
          @click="selectTimePeriod(option)"
        >
          <span>{{ t(option.labelI18nKey) }}</span>
          <span class="text-n-slate-11">{{ option.hour }}</span>
        </button>
      </div>
    </div>

    <div
      v-if="isCustomMode"
      class="flex-1 min-w-0 [&_.mx-datepicker]:w-full [&_.mx-input-wrapper]:w-full [&_.mx-input]:w-full [&_.mx-input]:!mb-0"
      :class="
        dateTimeError
          ? '[&_.mx-input]:!border-n-ruby-9 [&_.mx-input]:!border-solid'
          : ''
      "
      @click.stop
    >
      <DatePicker
        :value="customDateTime"
        :open="datePickerOpen"
        type="datetime"
        :placeholder="t('SCHEDULED_MESSAGES.MODAL.DATETIME_PLACEHOLDER')"
        :lang="datePickerLang"
        :format="t('SCHEDULED_MESSAGES.MODAL.DATETIME_FORMAT')"
        value-type="date"
        :disabled-date="disablePastDates"
        :show-second="false"
        editable
        clearable
        append-to-body
        popup-class="z-[10000]"
        @open="datePickerOpen = true"
        @close="datePickerOpen = false"
        @change="onCustomDateTimeChange"
      />
    </div>
  </div>
</template>
