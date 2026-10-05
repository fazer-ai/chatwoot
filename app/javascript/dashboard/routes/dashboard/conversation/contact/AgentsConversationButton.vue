<script setup>
import { computed, ref, watch } from 'vue';
import InboxesAPI from 'dashboard/api/inboxes';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { agentsConversationUrl } from 'dashboard/helper/agentsConversationLink';

const props = defineProps({
  conversation: {
    type: Object,
    default: null,
  },
});

const outgoingUrl = ref('');

watch(
  () => props.conversation?.inbox_id,
  async inboxId => {
    outgoingUrl.value = '';
    if (!inboxId) return;
    const { data } = await InboxesAPI.getAgentBot(inboxId);
    // A reply for an inbox the panel has already left must not light the button up on the next one.
    if (props.conversation?.inbox_id !== inboxId) return;
    outgoingUrl.value = data?.agent_bot?.outgoing_url || '';
  },
  { immediate: true }
);

const href = computed(() =>
  props.conversation
    ? agentsConversationUrl(outgoingUrl.value, {
        accountId: props.conversation.account_id,
        conversationId: props.conversation.id,
        inboxId: props.conversation.inbox_id,
      })
    : null
);

const open = () => window.open(href.value, '_blank', 'noopener');
</script>

<template>
  <NextButton
    v-if="href"
    v-tooltip.top-end="$t('CONTACT_PANEL.OPEN_IN_AGENTS')"
    icon="i-lucide-bot"
    slate
    faded
    sm
    @click="open"
  />
</template>
