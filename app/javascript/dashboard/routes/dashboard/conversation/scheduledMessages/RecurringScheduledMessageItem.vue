<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useToggle } from '@vueuse/core';

import NextButton from 'dashboard/components-next/button/Button.vue';
import { buildRecurrenceDescription } from 'dashboard/helper/recurrenceHelpers';

const props = defineProps({
  recurringMessage: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['stop']);

const { t, locale } = useI18n();
const [isExpanded, toggleExpand] = useToggle(false);

const statusBadgeClass = computed(() => {
  const map = {
    active: 'bg-n-teal-3 text-n-teal-11',
    completed: 'bg-n-slate-3 text-n-slate-11',
    cancelled: 'bg-n-ruby-3 text-n-ruby-11',
    draft: 'bg-n-amber-3 text-n-amber-11',
  };
  return map[props.recurringMessage.status] || 'bg-n-slate-3 text-n-slate-11';
});

const statusLabel = computed(() => {
  const key = props.recurringMessage.status?.toUpperCase();
  return t(`SCHEDULED_MESSAGES.RECURRENCE.STATUS_${key}`);
});

const recurrenceDescription = computed(() =>
  buildRecurrenceDescription(
    props.recurringMessage.recurrence_rule,
    locale.value
  )
);

const occurrencesSentLabel = computed(() =>
  t('SCHEDULED_MESSAGES.RECURRENCE.OCCURRENCES_SENT', {
    count: props.recurringMessage.occurrences_sent || 0,
  })
);

const nextSendLabel = computed(() => {
  const pending = props.recurringMessage.pending_scheduled_message;
  if (!pending?.scheduled_at) return null;
  const date = new Date(pending.scheduled_at * 1000);
  return t('SCHEDULED_MESSAGES.RECURRENCE.NEXT_SEND', {
    time: date.toLocaleString(locale.value, {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    }),
  });
});

const isActive = computed(() => props.recurringMessage.status === 'active');

const showStopConfirm = ref(false);

const onStop = () => {
  showStopConfirm.value = true;
};

const confirmStop = () => {
  emit('stop', props.recurringMessage);
  showStopConfirm.value = false;
};
</script>

<template>
  <div class="flex flex-col gap-2 rounded-xl border border-n-weak px-3 py-3">
    <!-- Header -->
    <div class="flex items-center justify-between gap-2">
      <div class="flex items-center gap-2 min-w-0">
        <i class="i-lucide-repeat text-n-slate-11 shrink-0" />
        <span class="text-sm font-medium text-n-slate-12 truncate">
          {{ recurrenceDescription }}
        </span>
      </div>
      <span
        class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium shrink-0"
        :class="statusBadgeClass"
      >
        {{ statusLabel }}
      </span>
    </div>

    <!-- Content Preview -->
    <p class="text-sm text-n-slate-11" :class="{ 'line-clamp-2': !isExpanded }">
      {{ recurringMessage.content }}
    </p>

    <!-- Meta Row -->
    <div class="flex items-center gap-3 text-xs text-n-slate-10">
      <span>{{ occurrencesSentLabel }}</span>
      <span v-if="nextSendLabel">·</span>
      <span v-if="nextSendLabel">{{ nextSendLabel }}</span>
    </div>

    <!-- Actions -->
    <div class="flex items-center gap-2 pt-1">
      <NextButton
        v-if="recurringMessage.content?.length > 80"
        ghost
        xs
        :icon="isExpanded ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        :label="
          isExpanded
            ? t('SCHEDULED_MESSAGES.RECURRENCE.COLLAPSE')
            : t('SCHEDULED_MESSAGES.RECURRENCE.EXPAND')
        "
        @click="toggleExpand()"
      />
      <NextButton
        v-if="isActive"
        ghost
        xs
        ruby
        icon="i-lucide-square"
        :label="t('SCHEDULED_MESSAGES.RECURRENCE.STOP')"
        @click="onStop"
      />
    </div>

    <!-- Stop Confirmation -->
    <woot-modal
      v-model:show="showStopConfirm"
      :on-close="() => (showStopConfirm = false)"
      size="small"
    >
      <div class="flex w-full flex-col gap-4 px-6 py-6">
        <h3 class="text-lg font-semibold text-n-slate-12">
          {{ t('SCHEDULED_MESSAGES.RECURRENCE.STOP_CONFIRM.TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11">
          {{ t('SCHEDULED_MESSAGES.RECURRENCE.STOP_CONFIRM.MESSAGE') }}
        </p>
        <div class="flex items-center justify-end gap-3">
          <NextButton
            ghost
            slate
            :label="t('SCHEDULED_MESSAGES.RECURRENCE.STOP_CONFIRM.CANCEL')"
            @click="showStopConfirm = false"
          />
          <NextButton
            solid
            ruby
            :label="t('SCHEDULED_MESSAGES.RECURRENCE.STOP_CONFIRM.CONFIRM')"
            @click="confirmStop"
          />
        </div>
      </div>
    </woot-modal>
  </div>
</template>
