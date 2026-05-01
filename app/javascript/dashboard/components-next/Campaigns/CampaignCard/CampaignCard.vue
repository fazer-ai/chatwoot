<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { useMapGetter } from 'dashboard/composables/store';
import { getInboxIconByType } from 'dashboard/helper/inbox';

import CardLayout from 'dashboard/components-next/CardLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import LiveChatCampaignDetails from './LiveChatCampaignDetails.vue';
import SMSCampaignDetails from './SMSCampaignDetails.vue';

const props = defineProps({
  title: {
    type: String,
    default: '',
  },
  message: {
    type: String,
    default: '',
  },
  isLiveChatType: {
    type: Boolean,
    default: false,
  },
  isEnabled: {
    type: Boolean,
    default: false,
  },
  status: {
    type: String,
    default: '',
  },
  sender: {
    type: Object,
    default: null,
  },
  inbox: {
    type: Object,
    default: null,
  },
  scheduledAt: {
    type: Number,
    default: 0,
  },
  templateParams: {
    type: Object,
    default: null,
  },
  audience: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['edit', 'delete']);

const { t } = useI18n();

const STATUS_COMPLETED = 'completed';

const { formatMessage } = useMessageFormatter();

const isActive = computed(() =>
  props.isLiveChatType ? props.isEnabled : props.status !== STATUS_COMPLETED
);

const statusTextColor = computed(() => ({
  'text-n-teal-11': isActive.value,
  'text-n-slate-12': !isActive.value,
}));

const campaignStatus = computed(() => {
  if (props.isLiveChatType) {
    return props.isEnabled
      ? t('CAMPAIGN.LIVE_CHAT.CARD.STATUS.ENABLED')
      : t('CAMPAIGN.LIVE_CHAT.CARD.STATUS.DISABLED');
  }

  return props.status === STATUS_COMPLETED
    ? t('CAMPAIGN.SMS.CARD.STATUS.COMPLETED')
    : t('CAMPAIGN.SMS.CARD.STATUS.SCHEDULED');
});

const inboxName = computed(() => props.inbox?.name || '');

const inboxIcon = computed(() => {
  const { medium, channel_type: type } = props.inbox;
  return getInboxIconByType(type, medium);
});

const accountLabels = useMapGetter('labels/getLabels');

const templateName = computed(() => props.templateParams?.name || '');

const audienceLabels = computed(() => {
  const audienceLabelIds = (props.audience || [])
    .filter(item => item?.type === 'Label')
    .map(item => Number(item.id));
  if (!audienceLabelIds.length) return [];

  const idToLabel = new Map(
    accountLabels.value.map(label => [Number(label.id), label])
  );
  return audienceLabelIds.map(id => {
    const match = idToLabel.get(id);
    return {
      id,
      title: match?.title || `#${id}`,
      color: match?.color || '#94a3b8',
    };
  });
});

const hasCampaignDetails = computed(
  () => templateName.value || audienceLabels.value.length
);
</script>

<template>
  <CardLayout layout="row">
    <div class="flex flex-col items-start justify-between flex-1 min-w-0 gap-2">
      <div class="flex justify-between gap-3 w-fit">
        <span
          class="text-base font-medium capitalize text-n-slate-12 line-clamp-1"
        >
          {{ title }}
        </span>
        <span
          class="text-xs font-medium inline-flex items-center h-6 px-2 py-0.5 rounded-md bg-n-alpha-2"
          :class="statusTextColor"
        >
          {{ campaignStatus }}
        </span>
      </div>
      <div
        v-dompurify-html="formatMessage(message, false, false, false)"
        class="text-sm text-n-slate-11 line-clamp-1 [&>p]:mb-0 h-6"
      />
      <div class="flex items-center w-full h-6 gap-2 overflow-hidden">
        <LiveChatCampaignDetails
          v-if="isLiveChatType"
          :sender="sender"
          :inbox-name="inboxName"
          :inbox-icon="inboxIcon"
        />
        <SMSCampaignDetails
          v-else
          :inbox-name="inboxName"
          :inbox-icon="inboxIcon"
          :scheduled-at="scheduledAt"
        />
      </div>
      <div
        v-if="hasCampaignDetails"
        class="flex flex-wrap items-center w-full gap-x-4 gap-y-1"
      >
        <div v-if="templateName" class="flex items-center gap-1.5 min-w-0">
          <span class="text-sm text-n-slate-11 whitespace-nowrap">
            {{ t('CAMPAIGN.WHATSAPP.CARD.TEMPLATE_LABEL') }}
          </span>
          <span
            class="text-sm font-medium truncate text-n-slate-12"
            :title="templateName"
          >
            {{ templateName }}
          </span>
        </div>
        <div
          v-if="audienceLabels.length"
          class="flex flex-wrap items-center gap-1.5 min-w-0"
        >
          <span class="text-sm text-n-slate-11 whitespace-nowrap">
            {{ t('CAMPAIGN.WHATSAPP.CARD.AUDIENCE_LABEL') }}
          </span>
          <span
            v-for="label in audienceLabels"
            :key="label.id"
            v-tooltip.top="label.title"
            class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium text-white truncate max-w-[140px]"
            :style="{ backgroundColor: label.color }"
          >
            {{ label.title }}
          </span>
        </div>
      </div>
    </div>
    <div class="flex items-center justify-end w-20 gap-2">
      <Button
        v-if="isLiveChatType"
        variant="faded"
        size="sm"
        color="slate"
        icon="i-lucide-sliders-vertical"
        @click="emit('edit')"
      />
      <Button
        variant="faded"
        color="ruby"
        size="sm"
        icon="i-lucide-trash"
        @click="emit('delete')"
      />
    </div>
  </CardLayout>
</template>
