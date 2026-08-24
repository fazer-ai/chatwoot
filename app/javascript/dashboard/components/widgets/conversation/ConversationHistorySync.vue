<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';

import NextButton from 'dashboard/components-next/button/Button.vue';

// The end of what this inbox holds, and the offer to ask the phone for more.
//
// Placed at the top of the thread rather than in a settings screen because that is where
// the want appears: somebody reading a conversation that starts mid-sentence. It is also
// the shape of the mechanism -- the provider walks one chat backwards from one anchor, so
// a control per chat is the honest surface for it.
//
// Always offered rather than shown only when there is more to fetch. WhatsApp does carry a
// per-chat "more remains on the primary device" flag, and measuring it on a real pairing
// found it set on 40 chats out of 640 and never once set to its "nothing remains" value:
// it can say there is more, never that there is not. A control that appeared on 6% of
// threads and vanished from the rest, where history may well exist, would be worse than
// one that is simply always there.
const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});

const store = useStore();
const { t } = useI18n();

// The phone answers on the webhook minutes later, or never -- it has to be awake and it
// declines to resend a stretch it has already handed over. So the press reports that the
// request went out, and the messages appear on their own above.
const requesting = ref(false);
const requestOlder = async () => {
  requesting.value = true;
  try {
    await store.dispatch('syncHistory', props.conversationId);
    useAlert(t('CONVERSATION.HISTORY_SYNC.REQUESTED'));
  } catch (error) {
    useAlert(t('CONVERSATION.HISTORY_SYNC.ERROR'));
  } finally {
    requesting.value = false;
  }
};
</script>

<template>
  <li class="flex flex-col items-center gap-1 py-3 list-none">
    <NextButton
      faded
      slate
      sm
      :is-loading="requesting"
      :disabled="requesting"
      @click="requestOlder"
    >
      {{ $t('CONVERSATION.HISTORY_SYNC.BUTTON') }}
    </NextButton>
    <span class="text-xs text-n-slate-11">
      {{ $t('CONVERSATION.HISTORY_SYNC.HELP') }}
    </span>
  </li>
</template>
