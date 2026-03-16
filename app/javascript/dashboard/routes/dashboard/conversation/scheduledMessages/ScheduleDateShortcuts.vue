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
  <div class="flex flex-col gap-2">
    <div class="flex flex-wrap items-center gap-2">
      <button
        v-for="shortcut in shortcuts"
        :key="shortcut.key"
        type="button"
        class="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm rounded-lg border transition-colors cursor-pointer"
        :class="
          selectedKey === shortcut.key
            ? 'border-n-brand bg-n-alpha-2 text-n-blue-text font-medium'
            : 'border-n-weak bg-n-background text-n-slate-11 hover:bg-n-alpha-1 hover:border-n-strong'
        "
        @click="onSelectShortcut(shortcut)"
      >
        <span>{{ t(shortcut.labelI18nKey) }}</span>
        <!-- eslint-disable-next-line @intlify/vue-i18n/no-raw-text -->
        <span
          class="text-xs"
          :class="
            selectedKey === shortcut.key
              ? 'text-n-blue-text/70'
              : 'text-n-slate-9'
          "
        >
          · {{ shortcut.detail }}
        </span>
      </button>
      <button
        type="button"
        class="inline-flex items-center px-3 py-1.5 text-sm rounded-lg border transition-colors cursor-pointer"
        :class="
          isCustomMode
            ? 'border-n-brand bg-n-alpha-2 text-n-blue-text font-medium'
            : 'border-n-weak bg-n-background text-n-slate-11 hover:bg-n-alpha-1 hover:border-n-strong'
        "
        @click="onSelectCustom"
      >
        {{ t('SCHEDULED_MESSAGES.MODAL.SHORTCUTS.CUSTOM') }}
      </button>
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
