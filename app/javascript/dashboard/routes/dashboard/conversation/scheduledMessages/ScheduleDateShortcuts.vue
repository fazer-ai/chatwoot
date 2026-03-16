<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import DatePicker from 'vue-datepicker-next';
import {
  SHORTCUT_KEYS,
  getScheduleShortcuts,
  getDatePickerLang,
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

const { t, locale } = useI18n();

const selectedKey = ref('');
const customDateTime = ref(null);

const isCustomMode = computed(() => selectedKey.value === SHORTCUT_KEYS.CUSTOM);

const shortcuts = computed(() =>
  getScheduleShortcuts(new Date(), locale.value)
);

const datePickerLang = computed(() => getDatePickerLang(locale.value));

const disablePastDates = date => {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return date < today;
};

const disablePastTimes = date => {
  const now = new Date();
  return date < now;
};

const onSelectShortcut = shortcut => {
  selectedKey.value = shortcut.key;
  emit('update:modelValue', shortcut.dateTime);
};

const onSelectCustom = () => {
  selectedKey.value = SHORTCUT_KEYS.CUSTOM;
  customDateTime.value = props.modelValue;
  emit('update:modelValue', null);
};

const onCustomDateTimeChange = value => {
  customDateTime.value = value;
  emit('update:modelValue', value);
};

// Sync local state when modelValue changes externally (edit mode or resetForm)
watch(
  () => props.modelValue,
  newValue => {
    if (!newValue) {
      if (!isCustomMode.value) {
        selectedKey.value = '';
      }
      customDateTime.value = null;
    } else if (!selectedKey.value || isCustomMode.value) {
      selectedKey.value = SHORTCUT_KEYS.CUSTOM;
      customDateTime.value = newValue;
    }
  },
  { immediate: true }
);
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex flex-col rounded-xl border border-n-weak bg-n-background">
      <button
        v-for="shortcut in shortcuts"
        :key="shortcut.key"
        type="button"
        class="flex items-center justify-between px-4 py-3 text-sm transition-colors border-b border-n-weak cursor-pointer first:rounded-t-xl"
        :class="
          selectedKey === shortcut.key
            ? 'bg-n-alpha-2 text-n-blue-text'
            : 'text-n-slate-12 hover:bg-n-alpha-1'
        "
        @click="onSelectShortcut(shortcut)"
      >
        <span :class="{ 'font-medium': selectedKey === shortcut.key }">
          {{ t(shortcut.labelI18nKey) }}
        </span>
        <!-- eslint-disable-next-line @intlify/vue-i18n/no-raw-text -->
        <span
          class="text-sm"
          :class="
            selectedKey === shortcut.key
              ? 'text-n-blue-text/70'
              : 'text-n-slate-9'
          "
        >
          {{ shortcut.detail }}
        </span>
      </button>

      <button
        type="button"
        class="flex items-center gap-2 px-4 py-3 text-sm transition-colors cursor-pointer rounded-b-xl"
        :class="
          isCustomMode
            ? 'bg-n-alpha-2 text-n-blue-text font-medium'
            : 'text-n-slate-12 hover:bg-n-alpha-1'
        "
        @click="onSelectCustom"
      >
        <span class="i-lucide-calendar size-4 shrink-0" />
        <span>{{ t('SCHEDULED_MESSAGES.MODAL.SHORTCUTS.CUSTOM') }}</span>
      </button>
    </div>

    <div
      v-if="isCustomMode"
      class="inline-datepicker-wrapper rounded-xl border border-n-weak bg-n-background p-3"
      :class="dateTimeError ? '!border-n-ruby-9' : ''"
    >
      <DatePicker
        v-model:value="customDateTime"
        type="datetime"
        inline
        :lang="datePickerLang"
        :disabled-date="disablePastDates"
        :disabled-time="disablePastTimes"
        :show-second="false"
        @change="onCustomDateTimeChange"
      />
    </div>
  </div>
</template>

<style scoped>
.inline-datepicker-wrapper :deep(.mx-datepicker-inline) {
  width: 100%;
}

.inline-datepicker-wrapper :deep(.mx-calendar) {
  width: 100%;
}

.inline-datepicker-wrapper :deep(.mx-calendar-content) {
  width: 100%;
}

.inline-datepicker-wrapper :deep(.mx-table) {
  width: 100%;
}

.inline-datepicker-wrapper :deep(.mx-table th),
.inline-datepicker-wrapper :deep(.mx-table td) {
  text-align: center;
}

.inline-datepicker-wrapper :deep(.mx-time) {
  width: 100%;
}
</style>
