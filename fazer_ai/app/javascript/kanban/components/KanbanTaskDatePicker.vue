<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import DatePicker from 'vue-datepicker-next';

const props = defineProps({
  startDate: {
    type: Date,
    default: null,
  },
  dueDate: {
    type: Date,
    default: null,
  },
  stacked: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update:startDate', 'update:dueDate']);

const { t } = useI18n();

const localStartDate = ref(props.startDate);
const localDueDate = ref(props.dueDate);
const startTime = ref(null);
const dueTime = ref(null);

// Check if start time was explicitly set (not default 00:00:00)
// We detect by checking milliseconds - defaults have ms=0, user-set also has ms=0
// For start date, any non-midnight time is explicit
const isExplicitStartTime = date => {
  if (!date) return false;
  const hours = date.getHours();
  const minutes = date.getMinutes();
  // If it's not midnight, it was explicitly set
  if (hours !== 0 || minutes !== 0) return true;
  // Midnight is ambiguous - could be default or explicit
  // We can't distinguish, so treat as not explicit
  return false;
};

// Check if due time was explicitly set (not default 23:59:59.999)
// Default due time is end of day (23:59:59.999), user-set times have seconds=0
const isExplicitDueTime = date => {
  if (!date) return false;
  const hours = date.getHours();
  const minutes = date.getMinutes();
  const seconds = date.getSeconds();
  // If seconds != 59, it was user-set (we save with seconds=0)
  if (hours === 23 && minutes === 59 && seconds === 59) return false;
  // Any other time was explicitly set
  return true;
};

// Sync props to local state
watch(
  () => props.startDate,
  val => {
    localStartDate.value = val;
    if (val && isExplicitStartTime(val)) {
      startTime.value = val;
    } else {
      startTime.value = null;
    }
  },
  { immediate: true }
);

watch(
  () => props.dueDate,
  val => {
    localDueDate.value = val;
    if (val && isExplicitDueTime(val)) {
      dueTime.value = val;
    } else {
      dueTime.value = null;
    }
  },
  { immediate: true }
);

// Helper to check if two dates are on the same calendar day
const isSameDay = (date1, date2) => {
  if (!date1 || !date2) return false;
  return (
    date1.getFullYear() === date2.getFullYear() &&
    date1.getMonth() === date2.getMonth() &&
    date1.getDate() === date2.getDate()
  );
};

// Emit combined date + time
const emitStartDate = () => {
  if (!localStartDate.value) {
    emit('update:startDate', null);
    return;
  }

  const date = new Date(localStartDate.value);
  if (startTime.value) {
    date.setHours(
      startTime.value.getHours(),
      startTime.value.getMinutes(),
      0,
      0
    );
  } else {
    // Default to start of day
    date.setHours(0, 0, 0, 0);
  }

  // Validate: if same day as due date and has explicit times, start must be before due
  if (
    localDueDate.value &&
    isSameDay(date, localDueDate.value) &&
    startTime.value &&
    dueTime.value
  ) {
    const dueDateTime = new Date(localDueDate.value);
    dueDateTime.setHours(dueTime.value.getHours(), dueTime.value.getMinutes());
    if (date > dueDateTime) {
      // Adjust due time to match start time
      emit('update:dueDate', new Date(date));
    }
  }

  emit('update:startDate', date);
};

const emitDueDate = () => {
  if (!localDueDate.value) {
    emit('update:dueDate', null);
    return;
  }

  const date = new Date(localDueDate.value);
  if (dueTime.value) {
    date.setHours(dueTime.value.getHours(), dueTime.value.getMinutes(), 0, 0);
  } else {
    // Default to end of day
    date.setHours(23, 59, 59, 999);
  }

  // Validate: if same day as start date and has explicit times, due must be after start
  if (
    localStartDate.value &&
    isSameDay(date, localStartDate.value) &&
    startTime.value &&
    dueTime.value
  ) {
    const startDateTime = new Date(localStartDate.value);
    startDateTime.setHours(
      startTime.value.getHours(),
      startTime.value.getMinutes()
    );
    if (date < startDateTime) {
      // Adjust start time to match due time
      emit('update:startDate', new Date(date));
    }
  }

  emit('update:dueDate', date);
};

// Validation: due date must not be before start date
const disabledDueDate = date => {
  if (!localStartDate.value) return false;
  const startDay = new Date(localStartDate.value);
  startDay.setHours(0, 0, 0, 0);
  return date < startDay;
};

const disabledStartDate = date => {
  if (!localDueDate.value) return false;
  const dueDay = new Date(localDueDate.value);
  dueDay.setHours(23, 59, 59, 999);
  return date > dueDay;
};

const onStartDateChange = val => {
  localStartDate.value = val;
  emitStartDate();
};

const onDueDateChange = val => {
  localDueDate.value = val;
  emitDueDate();
};

const onStartTimeChange = val => {
  startTime.value = val;
  emitStartDate();
};

const onDueTimeChange = val => {
  dueTime.value = val;
  emitDueDate();
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
</script>

<template>
  <div
    :class="props.stacked ? 'flex flex-col gap-3' : 'grid grid-cols-2 gap-4'"
  >
    <!-- Start Date -->
    <div class="flex flex-col gap-2 min-w-0">
      <span class="text-sm font-medium text-n-slate-12 select-none">
        {{ t('KANBAN.MODAL.START_DATE_LABEL') }}
      </span>
      <div class="kanban-date-picker-wrapper">
        <DatePicker
          :value="localStartDate"
          type="date"
          :placeholder="t('KANBAN.MODAL.START_DATE_PLACEHOLDER')"
          :lang="datePickerLang"
          :format="t('KANBAN.DATE.DATE_FORMAT')"
          value-type="date"
          editable
          :disabled-date="disabledStartDate"
          :append-to-body="false"
          @change="onStartDateChange"
        />
      </div>
      <div v-if="localStartDate" class="kanban-date-picker-wrapper">
        <DatePicker
          :value="startTime"
          type="time"
          :placeholder="t('KANBAN.DATE.TIME_PLACEHOLDER')"
          :lang="datePickerLang"
          :format="t('KANBAN.DATE.TIME_FORMAT')"
          value-type="date"
          editable
          :append-to-body="false"
          @change="onStartTimeChange"
        />
      </div>
    </div>

    <!-- Due Date -->
    <div class="flex flex-col gap-2 min-w-0">
      <span class="text-sm font-medium text-n-slate-12 select-none">
        {{ t('KANBAN.MODAL.DUE_DATE_LABEL') }}
      </span>
      <div class="kanban-date-picker-wrapper">
        <DatePicker
          :value="localDueDate"
          type="date"
          :placeholder="t('KANBAN.MODAL.DUE_DATE_PLACEHOLDER')"
          :lang="datePickerLang"
          :format="t('KANBAN.DATE.DATE_FORMAT')"
          value-type="date"
          editable
          :disabled-date="disabledDueDate"
          :append-to-body="false"
          @change="onDueDateChange"
        />
      </div>
      <div v-if="localDueDate" class="kanban-date-picker-wrapper">
        <DatePicker
          :value="dueTime"
          type="time"
          :placeholder="t('KANBAN.DATE.TIME_PLACEHOLDER')"
          :lang="datePickerLang"
          :format="t('KANBAN.DATE.TIME_FORMAT')"
          value-type="date"
          editable
          :append-to-body="false"
          @change="onDueTimeChange"
        />
      </div>
    </div>
  </div>
</template>

<style>
.kanban-date-picker-wrapper {
  width: 100%;
  min-width: 0;
}

.kanban-date-picker-wrapper .mx-datepicker {
  width: 100%;
}

.kanban-date-picker-wrapper .mx-input-wrapper {
  width: 100%;
}

.kanban-date-picker-wrapper .mx-input {
  width: 100%;
}
</style>
