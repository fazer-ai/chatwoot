<script setup>
import { inject, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { CONTACT_CONVERSATION_NAVIGATION } from 'dashboard/composables/useContactConversationNavigation';

import NextButton from 'dashboard/components-next/button/Button.vue';

// The end of what this inbox holds, and either the offer to ask the phone for more or
// the word that there is no more to ask for.
//
// Placed at the top of the thread rather than in a settings screen because that is where
// the want appears: somebody reading a conversation that starts mid-sentence. It is also
// the shape of the mechanism -- the provider walks one chat backwards from one anchor, so
// a control per chat is the honest surface for it.
//
// WhatsApp only ever says a chat is finished on the answer to a request, never before
// one, so the two states are ordered rather than alternative: the offer stands until an
// answer retires it, which is the same order WhatsApp Web shows them in.

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  exhausted: { type: Boolean, default: false },
});

const store = useStore();
const { t } = useI18n();
// The same move as the previous-conversation link, so the older thread opens as history.
const { openConversation } = inject(CONTACT_CONVERSATION_NAVIGATION);

// The phone answers on the webhook minutes later, or never -- it has to be awake and it
// declines to resend a stretch it has already handed over. So the press reports that the
// request went out, and the messages appear on their own above.
//
// The answer is filed by date, so it lands in the thread that was current before the
// anchor the request pages back from, which is often an older one than this. The server
// names it (`filed_in`) and the agent is taken there to watch it arrive; `null` is a
// thread the agent may not open.
const requesting = ref(false);
const requestOlder = async () => {
  requesting.value = true;
  try {
    const { filed_in: filedIn } = await store.dispatch(
      'syncHistory',
      props.conversationId
    );
    if (!filedIn) {
      useAlert(t('CONVERSATION.HISTORY_SYNC.REQUESTED_HIDDEN'));
    } else if (filedIn !== Number(props.conversationId)) {
      useAlert(t('CONVERSATION.HISTORY_SYNC.REQUESTED_ELSEWHERE', { filedIn }));
      openConversation({ id: filedIn });
    } else {
      useAlert(t('CONVERSATION.HISTORY_SYNC.REQUESTED'));
    }
  } catch (error) {
    useAlert(t('CONVERSATION.HISTORY_SYNC.ERROR'));
  } finally {
    requesting.value = false;
  }
};
</script>

<template>
  <li class="flex flex-col items-center gap-1 py-3 list-none">
    <span v-if="exhausted" class="text-xs text-n-slate-11">
      {{ $t('CONVERSATION.HISTORY_SYNC.EXHAUSTED') }}
    </span>
    <NextButton
      v-if="!exhausted"
      faded
      slate
      sm
      :is-loading="requesting"
      :disabled="requesting"
      @click="requestOlder"
    >
      {{ $t('CONVERSATION.HISTORY_SYNC.BUTTON') }}
    </NextButton>
    <span v-if="!exhausted" class="text-xs text-n-slate-11">
      {{ $t('CONVERSATION.HISTORY_SYNC.HELP') }}
    </span>
  </li>
</template>
