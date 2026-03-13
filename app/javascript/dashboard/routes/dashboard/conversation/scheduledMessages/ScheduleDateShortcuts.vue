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

const selectedDay = ref('');
const selectedTimePeriod = ref('');
const customDateTime = ref(null);

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
    selectedTimePeriod.value = '';
    return;
  }
  const targetDate = getShortcutDate(newDay);
  const firstAvailable = [
    SCHEDULE_TIME_PERIODS.MORNING,
    SCHEDULE_TIME_PERIODS.AFTERNOON,
    SCHEDULE_TIME_PERIODS.EVENING,
  ].find(tp => !isTimePeriodPast(targetDate, tp));
  selectedTimePeriod.value = firstAvailable || '';
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

// Sync local state when modelValue changes externally (edit mode or resetForm)
watch(
  () => props.modelValue,
  newValue => {
    if (!newValue) {
      selectedDay.value = '';
      selectedTimePeriod.value = '';
      customDateTime.value = null;
    } else if (!selectedDay.value) {
      // Pre-existing value (e.g. edit mode) — open in Custom mode
      selectedDay.value = SCHEDULE_DAY_OPTIONS.CUSTOM;
      customDateTime.value = newValue;
    }
  },
  { immediate: true }
);

const onDayChange = event => {
  const key = event.target.value;
  selectedDay.value = key;
  if (key === SCHEDULE_DAY_OPTIONS.CUSTOM) {
    customDateTime.value = props.modelValue;
  }
};

const onTimePeriodChange = event => {
  selectedTimePeriod.value = event.target.value;
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

const dayOptionLabel = option => {
  const label = t(option.labelI18nKey);
  return option.formattedDate ? `${label} ${option.formattedDate}` : label;
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex items-center gap-3">
      <select
        :value="selectedDay"
        class="block w-full px-3 py-2 pr-6 mb-0 text-sm border-0 shadow-sm appearance-none rounded-xl select-caret leading-6"
        :class="{
          'text-n-slate-9': !selectedDay,
          'text-n-slate-12': selectedDay,
        }"
        @change="onDayChange"
      >
        <option value="" disabled selected hidden>
          {{ t('SCHEDULED_MESSAGES.MODAL.SHORTCUTS.DAYS_LABEL') }}
        </option>
        <option
          v-for="option in dayOptions"
          :key="option.key"
          :value="option.key"
        >
          {{ dayOptionLabel(option) }}
        </option>
      </select>

      <select
        v-if="selectedDay && !isCustomMode"
        :value="selectedTimePeriod"
        class="block w-full px-3 py-2 pr-6 mb-0 text-sm border-0 shadow-sm appearance-none rounded-xl select-caret leading-6"
        :class="{
          'text-n-slate-9': !selectedTimePeriod,
          'text-n-slate-12': selectedTimePeriod,
        }"
        @change="onTimePeriodChange"
      >
        <option value="" disabled selected hidden>
          {{ t('SCHEDULED_MESSAGES.MODAL.SHORTCUTS.TIMES_LABEL') }}
        </option>
        <option
          v-for="option in timePeriodOptions"
          :key="option.key"
          :value="option.key"
          :disabled="option.disabled"
        >
          {{ t(option.labelI18nKey) }} ({{ option.hour }})
        </option>
      </select>
    </div>

    <div
      v-if="isCustomMode"
      class="flex-1 min-w-0 [&_.mx-datepicker]:w-full [&_.mx-input-wrapper]:w-full [&_.mx-input]:w-full [&_.mx-input]:!mb-0"
      :class="
        dateTimeError
          ? '[&_.mx-input]:!border-n-ruby-9 [&_.mx-input]:!border-solid'
          : ''
      "
    >
      <DatePicker
        :value="customDateTime"
        type="datetime"
        :placeholder="t('SCHEDULED_MESSAGES.MODAL.DATETIME_PLACEHOLDER')"
        :lang="datePickerLang"
        :format="t('SCHEDULED_MESSAGES.MODAL.DATETIME_FORMAT')"
        value-type="date"
        :disabled-date="disablePastDates"
        :show-second="false"
        confirm
        editable
        clearable
        append-to-body
        popup-class="z-[10000]"
        @change="onCustomDateTimeChange"
      />
    </div>
  </div>
</template>
