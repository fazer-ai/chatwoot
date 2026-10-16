<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import InboxesAPI from 'dashboard/api/inboxes';
import { canCheckWhatsappNumber } from 'dashboard/helper/whatsappNumberMissing';

const props = defineProps({
  targetInbox: { type: Object, default: null },
  selectedContact: { type: Object, default: null },
});

const { t } = useI18n();

const isMissing = ref(false);

// The search results are camelCased and the contact opened from its own page is not.
const phoneNumber = computed(
  () =>
    props.selectedContact?.phoneNumber ||
    props.selectedContact?.phone_number ||
    ''
);

// Only an explicit "no" warns. A failed or slow lookup is "unknown", and it never blocks
// the send either way: the agent may know something the lookup does not.
let lookupId = 0;
watch(
  () => [props.targetInbox?.id, phoneNumber.value],
  async () => {
    lookupId += 1;
    const currentLookup = lookupId;
    isMissing.value = false;
    if (!phoneNumber.value || !canCheckWhatsappNumber(props.targetInbox)) {
      return;
    }

    try {
      const { data } = await InboxesAPI.onWhatsapp(
        props.targetInbox.id,
        phoneNumber.value
      );
      if (currentLookup === lookupId) isMissing.value = data?.exists === false;
    } catch {
      // Unknown is not "no".
    }
  },
  { immediate: true }
);
</script>

<template>
  <div
    v-if="isMissing"
    role="alert"
    class="flex items-center gap-2 w-full px-4 py-3 dark:bg-n-amber-11/15 bg-n-amber-3"
  >
    <span class="i-lucide-triangle-alert size-4 shrink-0 text-n-amber-11" />
    <span class="text-sm text-n-amber-11">
      {{ t('COMPOSE_NEW_CONVERSATION.FORM.WHATSAPP_NUMBER_MISSING') }}
    </span>
  </div>
</template>
