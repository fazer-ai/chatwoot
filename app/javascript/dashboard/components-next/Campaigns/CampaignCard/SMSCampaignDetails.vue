<script setup>
import { computed } from 'vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { messageStamp } from 'shared/helpers/timeHelper';
import { resolveDateFnsLocale } from 'dashboard/helper/dateFnsLocale';

import { useI18n } from 'vue-i18n';
const props = defineProps({
  inboxName: {
    type: String,
    default: '',
  },
  inboxIcon: {
    type: String,
    default: '',
  },
  scheduledAt: {
    type: Number,
    default: 0,
  },
});

const { t, locale } = useI18n();
const dateFnsLocale = computed(() => resolveDateFnsLocale(locale.value));
const scheduledAtLabel = computed(() =>
  messageStamp(
    new Date(props.scheduledAt),
    'LLL d, h:mm a',
    dateFnsLocale.value
  )
);
</script>

<template>
  <span class="flex-shrink-0 text-sm text-n-slate-11 whitespace-nowrap">
    {{ t('CAMPAIGN.SMS.CARD.CAMPAIGN_DETAILS.SENT_FROM') }}
  </span>
  <div class="flex items-center gap-1.5 flex-shrink-0">
    <Icon :icon="inboxIcon" class="flex-shrink-0 text-n-slate-12 size-3" />
    <span class="text-sm font-medium text-n-slate-12">
      {{ inboxName }}
    </span>
  </div>

  <span class="flex-shrink-0 text-sm text-n-slate-11 whitespace-nowrap">
    {{ t('CAMPAIGN.SMS.CARD.CAMPAIGN_DETAILS.ON') }}
  </span>
  <span class="flex-1 text-sm font-medium truncate text-n-slate-12">
    {{ scheduledAtLabel }}
  </span>
</template>
