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
const [isContentExpanded, toggleContent] = useToggle(false);
const showHistory = ref(false);

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

const normalizedLocale = computed(() => locale.value.replace('_', '-'));

const recurrenceDescription = computed(() =>
  buildRecurrenceDescription(
    props.recurringMessage.recurrence_rule,
    normalizedLocale.value
  )
);

const childStatusConfig = {
  sent: {
    labelKey: 'SCHEDULED_MESSAGES.STATUS.SENT',
    class: 'bg-n-teal-9/10 text-n-teal-11',
    icon: 'i-lucide-check-circle',
  },
  failed: {
    labelKey: 'SCHEDULED_MESSAGES.STATUS.FAILED',
    class: 'bg-n-ruby-9/10 text-n-ruby-11',
    icon: 'i-lucide-x-circle',
  },
  pending: {
    labelKey: 'SCHEDULED_MESSAGES.STATUS.PENDING',
    class: 'bg-n-brand/10 text-n-blue-text',
    icon: 'i-lucide-clock',
  },
};

const completedChildren = computed(() => {
  const children = props.recurringMessage.scheduled_messages || [];
  return children
    .filter(m => ['sent', 'failed'].includes(m.status))
    .sort((a, b) => (b.scheduled_at || 0) - (a.scheduled_at || 0));
});

const hasCompletedChildren = computed(() => completedChildren.value.length > 0);

const formatChildTime = scheduledAt => {
  if (!scheduledAt) return '';
  const date = new Date(scheduledAt * 1000);
  const now = new Date();
  const options = {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  };
  if (date.getFullYear() !== now.getFullYear()) {
    options.year = 'numeric';
  }
  return date.toLocaleString(normalizedLocale.value, options);
};

const nextSendLabel = computed(() => {
  const pending = props.recurringMessage.pending_scheduled_message;
  if (!pending?.scheduled_at) return null;
  const date = new Date(pending.scheduled_at * 1000);
  return t('SCHEDULED_MESSAGES.RECURRENCE.NEXT_SEND', {
    time: date.toLocaleString(normalizedLocale.value, {
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
    <p
      class="text-sm text-n-slate-11"
      :class="{ 'line-clamp-2': !isContentExpanded }"
    >
      {{ recurringMessage.content }}
    </p>

    <!-- Meta Row -->
    <div class="flex items-center gap-3 text-xs text-n-slate-10">
      <button
        v-if="hasCompletedChildren"
        class="flex items-center gap-1 hover:text-n-slate-12 cursor-pointer transition-colors"
        @click="showHistory = !showHistory"
      >
        <i
          class="text-xs"
          :class="showHistory ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        />
        <span>
          {{
            t('SCHEDULED_MESSAGES.RECURRENCE.OCCURRENCES_SENT', {
              count: completedChildren.length,
            })
          }}
        </span>
      </button>
      <span v-else>
        {{ t('SCHEDULED_MESSAGES.RECURRENCE.OCCURRENCES_SENT', { count: 0 }) }}
      </span>
      <span v-if="nextSendLabel" class="text-n-slate-10">·</span>
      <span v-if="nextSendLabel">{{ nextSendLabel }}</span>
    </div>

    <!-- History of sent/failed children -->
    <div
      v-if="showHistory && hasCompletedChildren"
      class="flex flex-col gap-1 border-t border-n-weak pt-2"
    >
      <div
        v-for="child in completedChildren"
        :key="child.id"
        class="flex items-center justify-between gap-2 rounded-lg px-2 py-1.5 text-xs"
      >
        <div class="flex items-center gap-2 min-w-0">
          <i
            class="shrink-0 text-xs"
            :class="[
              childStatusConfig[child.status]?.icon || 'i-lucide-circle',
              child.status === 'sent' ? 'text-n-teal-11' : 'text-n-ruby-11',
            ]"
          />
          <span class="text-n-slate-11">
            {{ formatChildTime(child.scheduled_at) }}
          </span>
        </div>
        <span
          class="inline-flex items-center rounded-full px-1.5 py-0.5 text-[10px] font-medium shrink-0"
          :class="childStatusConfig[child.status]?.class"
        >
          {{ t(childStatusConfig[child.status]?.labelKey) }}
        </span>
      </div>
    </div>

    <!-- Actions -->
    <div class="flex items-center gap-2 pt-1">
      <NextButton
        v-if="recurringMessage.content?.length > 80"
        ghost
        xs
        :icon="
          isContentExpanded ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
        "
        :label="
          isContentExpanded
            ? t('SCHEDULED_MESSAGES.RECURRENCE.COLLAPSE')
            : t('SCHEDULED_MESSAGES.RECURRENCE.EXPAND')
        "
        @click="toggleContent()"
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
