<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import DropdownContainer from 'next/dropdown-menu/base/DropdownContainer.vue';
import DropdownBody from 'next/dropdown-menu/base/DropdownBody.vue';
import DropdownSection from 'next/dropdown-menu/base/DropdownSection.vue';
import DropdownItem from 'next/dropdown-menu/base/DropdownItem.vue';

import {
  getRecurrenceShortcuts,
  formatShortcutLabel,
  buildRecurrenceDescription,
} from 'dashboard/helper/recurrenceHelpers';

const props = defineProps({
  modelValue: {
    type: Object,
    default: null,
  },
  scheduledDate: {
    type: Date,
    default: null,
  },
});

const emit = defineEmits(['update:modelValue', 'openCustom']);

const { t, locale } = useI18n();

const shortcuts = computed(() => {
  if (!props.scheduledDate) return [];
  return getRecurrenceShortcuts(props.scheduledDate);
});

const selectedLabel = computed(() => {
  if (!props.modelValue) {
    return t('SCHEDULED_MESSAGES.RECURRENCE.NO_REPEAT');
  }

  const match = shortcuts.value.find(
    s => s.value && JSON.stringify(s.value) === JSON.stringify(props.modelValue)
  );

  if (match) {
    return formatShortcutLabel(match, t, locale.value);
  }

  return buildRecurrenceDescription(props.modelValue, locale.value);
});

const onSelect = shortcut => {
  if (shortcut.value === 'custom') {
    emit('openCustom');
  } else {
    emit('update:modelValue', shortcut.value);
  }
};
</script>

<template>
  <div v-if="scheduledDate" class="flex flex-col gap-1">
    <span class="text-sm font-medium text-n-slate-12">
      {{ t('SCHEDULED_MESSAGES.RECURRENCE.SECTION_TITLE') }}
    </span>
    <DropdownContainer>
      <template #trigger="{ toggle }">
        <button
          class="flex items-center gap-2 rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-1 w-full justify-between"
          @click="toggle"
        >
          <div class="flex items-center gap-2">
            <i
              class="i-lucide-repeat text-n-slate-11"
              :class="{ 'text-n-blue-10': modelValue }"
            />
            <span>{{ selectedLabel }}</span>
          </div>
          <i class="i-lucide-chevron-down text-n-slate-11" />
        </button>
      </template>
      <DropdownBody class="min-w-[280px] z-[10000]">
        <DropdownSection>
          <DropdownItem
            v-for="shortcut in shortcuts"
            :key="shortcut.label"
            :label="formatShortcutLabel(shortcut, t, locale)"
            :icon="
              shortcut.label === 'CUSTOM'
                ? 'i-lucide-settings-2'
                : 'i-lucide-repeat'
            "
            :class="{
              'bg-n-alpha-1':
                JSON.stringify(shortcut.value) === JSON.stringify(modelValue),
            }"
            :click="() => onSelect(shortcut)"
          />
        </DropdownSection>
      </DropdownBody>
    </DropdownContainer>
  </div>
</template>
