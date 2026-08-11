<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  status: { type: String, required: true },
});

const { t } = useI18n();

// Meta template statuses grouped by visual severity. Anything unmapped
// falls into the neutral bucket so a new status introduced by Meta
// still renders (just without a specific color).
const CLASSES = {
  approved: 'bg-n-teal-3 text-n-teal-12 border-n-teal-6',
  pending: 'bg-n-amber-3 text-n-amber-12 border-n-amber-6',
  danger: 'bg-n-ruby-3 text-n-ruby-12 border-n-ruby-6',
  neutral: 'bg-n-slate-3 text-n-slate-12 border-n-slate-6',
};

const bucket = computed(() => {
  switch ((props.status || '').toUpperCase()) {
    case 'APPROVED':
      return 'approved';
    case 'PENDING':
    case 'IN_APPEAL':
      return 'pending';
    case 'REJECTED':
    case 'PAUSED':
    case 'DISABLED':
      return 'danger';
    default:
      return 'neutral';
  }
});

const label = computed(() => {
  const key = (props.status || 'UNKNOWN').toUpperCase();
  return t(`META_TEMPLATES.STATUS.${key}`, key);
});
</script>

<template>
  <span
    :class="`inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border ${CLASSES[bucket]}`"
  >
    {{ label }}
  </span>
</template>
