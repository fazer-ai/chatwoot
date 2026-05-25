<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import { resolveDateFnsLocale } from 'dashboard/helper/dateFnsLocale';
import BaseBubble from './Base.vue';
import { useMessageContext } from '../provider.js';

const { content, createdAt } = useMessageContext();
const { locale } = useI18n();

const readableTime = computed(() =>
  messageTimestamp(
    createdAt.value,
    'LLL d, h:mm a',
    resolveDateFnsLocale(locale.value)
  )
);
</script>

<template>
  <BaseBubble
    v-tooltip.top="readableTime"
    class="px-3 py-1 !rounded-xl flex min-w-0 items-center gap-2"
    data-bubble-name="activity"
  >
    <span v-dompurify-html="content" :title="content" />
  </BaseBubble>
</template>
