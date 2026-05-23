<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';

const props = defineProps({
  messageId: { type: Number, required: true },
});

const store = useStore();
const reactionsByMessageId = computed(
  () => store.getters['conversation/getReactionsByMessageId'] || {}
);
const reactions = computed(
  () => reactionsByMessageId.value[props.messageId] || {}
);
const contactReaction = computed(() => reactions.value.contact?.emoji || '');
const agentReaction = computed(() => reactions.value.agent?.emoji || '');

const onChipClick = () => {
  if (!contactReaction.value) return;
  // Re-send our active emoji to remove (backend toggle).
  store.dispatch('conversation/toggleReaction', {
    messageId: props.messageId,
    emoji: contactReaction.value,
  });
};
</script>

<template>
  <div v-if="contactReaction || agentReaction" class="reaction-chips">
    <button
      v-if="contactReaction"
      type="button"
      class="reaction-chip reaction-chip--contact"
      :aria-label="`${contactReaction}`"
      @click.stop="onChipClick"
    >
      {{ contactReaction }}
    </button>
    <span
      v-if="agentReaction"
      class="reaction-chip reaction-chip--agent"
      :aria-label="`${agentReaction}`"
    >
      {{ agentReaction }}
    </span>
  </div>
</template>

<style lang="scss" scoped>
.reaction-chips {
  position: absolute;
  bottom: -10px;
  inset-inline-end: 6px;
  display: inline-flex;
  gap: 2px;
  z-index: 2;
}

.reaction-chip {
  background-color: #ffffff;
  border-radius: 9999px;
  padding: 1px 6px;
  font-size: 0.75rem;
  box-shadow: 0 1px 2px rgba(11, 20, 26, 0.15);

  .dark & {
    background-color: #1f2c34;
    color: #e9edef;
  }
}

.reaction-chip--contact {
  cursor: pointer;
}
</style>
