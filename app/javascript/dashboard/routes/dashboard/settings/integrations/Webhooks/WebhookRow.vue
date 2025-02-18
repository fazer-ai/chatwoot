<script setup>
import { computed } from 'vue';
import { getI18nKey } from 'dashboard/routes/dashboard/settings/helper/settingsHelper';
import ShowMore from 'dashboard/components/widgets/ShowMore.vue';
import { useI18n } from 'vue-i18n';
import LabelItem from 'dashboard/components-next/Label/LabelItem.vue';
import {
  amber,
  blue,
  cyan,
  jade,
  lime,
  mint,
  olive,
  orange,
  ruby,
  slate,
  teal,
  yellow,
} from '@radix-ui/colors';

const props = defineProps({
  webhook: {
    type: Object,
    required: true,
  },
  index: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['edit', 'delete']);
const { t } = useI18n();
const subscribedEvents = computed(() => {
  const { subscriptions } = props.webhook;
  return subscriptions
    .map(event =>
      t(
        getI18nKey(
          'INTEGRATION_SETTINGS.WEBHOOK.FORM.SUBSCRIPTIONS.EVENTS',
          event
        )
      )
    )
    .join(', ');
});

const COLORS = [
  jade.jade9,
  blue.blue9,
  ruby.ruby9,
  amber.amber9,
  slate.slate9,
  teal.teal9,
  orange.orange9,
  yellow.yellow9,
  lime.lime9,
  mint.mint9,
  olive.olive9,
  cyan.cyan9,
];
</script>

<template>
  <tr>
    <td class="py-4 ltr:pr-4 rtl:pl-4">
      <div
        class="flex gap-2 font-medium break-words text-slate-700 dark:text-slate-100"
      >
        <template v-if="webhook.name">
          {{ webhook.name }}
          <span class="text-slate-500 dark:text-slate-400">
            {{ webhook.url }}
          </span>
        </template>
        <template v-else>
          {{ webhook.url }}
        </template>
      </div>
      <div class="block mt-1 text-sm text-slate-500 dark:text-slate-400">
        <span class="font-medium">
          {{ $t('INTEGRATION_SETTINGS.WEBHOOK.SUBSCRIBED_EVENTS') }}:
        </span>
        <ShowMore :text="subscribedEvents" :limit="60" />
      </div>
      <div
        v-if="webhook.inbox"
        class="flex gap-2 font-medium break-words text-slate-500 dark:text-slate-400"
      >
        <LabelItem
          :label="{
            id: webhook.inbox.id,
            title: webhook.inbox.name,
            color: COLORS[webhook.inbox.id % COLORS.length],
          }"
        />
      </div>
    </td>
    <td class="py-4 min-w-xs">
      <div class="flex justify-end gap-1">
        <woot-button
          v-tooltip.top="$t('INTEGRATION_SETTINGS.WEBHOOK.EDIT.BUTTON_TEXT')"
          variant="smooth"
          size="tiny"
          color-scheme="secondary"
          icon="edit"
          @click="emit('edit', webhook)"
        />
        <woot-button
          v-tooltip.top="$t('INTEGRATION_SETTINGS.WEBHOOK.DELETE.BUTTON_TEXT')"
          variant="smooth"
          color-scheme="alert"
          size="tiny"
          icon="dismiss-circle"
          @click="emit('delete', webhook, index)"
        />
      </div>
    </td>
  </tr>
</template>
