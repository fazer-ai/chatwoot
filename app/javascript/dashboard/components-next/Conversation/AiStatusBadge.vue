<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  conversationId: { type: Number, required: true },
  aiEnabled: { type: Boolean, default: true },
});

const { t } = useI18n();
const store = useStore();
const isToggling = ref(false);

const toggle = async () => {
  if (isToggling.value) return;
  isToggling.value = true;
  try {
    await store.dispatch('toggleAiStatus', {
      conversationId: props.conversationId,
    });
  } catch (error) {
    useAlert(t('CONVERSATION.AI_STATUS.TOGGLE_ERROR'));
  } finally {
    isToggling.value = false;
  }
};
</script>

<template>
  <button
    type="button"
    class="inline-flex items-center gap-1 h-4 px-1.5 py-0.5 rounded-[4px] text-xs font-medium leading-tight flex-shrink-0 transition-opacity hover:opacity-90 disabled:opacity-60 cursor-pointer"
    :class="aiEnabled ? 'bg-n-teal-9 text-white' : 'bg-n-ruby-9 text-white'"
    :disabled="isToggling"
    :title="
      aiEnabled
        ? t('CONVERSATION.AI_STATUS.TOGGLE_OFF_TOOLTIP')
        : t('CONVERSATION.AI_STATUS.TOGGLE_ON_TOOLTIP')
    "
    @click.stop.prevent="toggle"
  >
    <span class="inline-block w-2 h-2 rounded-sm bg-white" />
    {{ t('CONVERSATION.AI_STATUS.LABEL') }}
  </button>
</template>
