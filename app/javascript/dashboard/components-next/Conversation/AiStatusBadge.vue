<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  conversationId: { type: Number, required: true },
  aiEnabled: { type: Boolean, default: true },
  size: {
    type: String,
    default: 'sm',
    validator: value => ['xs', 'sm'].includes(value),
  },
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
    class="inline-flex items-center gap-1 rounded font-medium flex-shrink-0 transition-opacity hover:opacity-90 disabled:opacity-60 cursor-pointer"
    :class="[
      aiEnabled ? 'bg-n-teal-9 text-white' : 'bg-n-ruby-9 text-white',
      size === 'xs' ? 'text-[10px] px-1.5 py-0.5' : 'text-xs px-2 py-0.5',
    ]"
    :disabled="isToggling"
    :title="
      aiEnabled
        ? t('CONVERSATION.AI_STATUS.TOGGLE_OFF_TOOLTIP')
        : t('CONVERSATION.AI_STATUS.TOGGLE_ON_TOOLTIP')
    "
    @click.stop.prevent="toggle"
  >
    <span class="size-1.5 rounded-full bg-white" />
    {{
      aiEnabled
        ? t('CONVERSATION.AI_STATUS.AI_ON')
        : t('CONVERSATION.AI_STATUS.AI_OFF')
    }}
  </button>
</template>
