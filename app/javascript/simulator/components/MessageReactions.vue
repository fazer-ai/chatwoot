<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';

const props = defineProps({
  messageId: { type: Number, required: true },
});

const store = useStore();
const isPickerOpen = ref(false);

// Six WhatsApp-style quick-reaction options. Keeping the set small
// matches the WhatsApp UX and side-steps building a full emoji picker
// (the SDK has one already, but it's wired into the input footer).
const QUICK_EMOJIS = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

const reactionsByMessageId = computed(
  () => store.getters['conversation/getReactionsByMessageId'] || {}
);
const reactions = computed(
  () => reactionsByMessageId.value[props.messageId] || {}
);
const contactReaction = computed(() => reactions.value.contact?.emoji || '');
const agentReaction = computed(() => reactions.value.agent?.emoji || '');

const togglePicker = () => {
  isPickerOpen.value = !isPickerOpen.value;
};

const closePicker = () => {
  isPickerOpen.value = false;
};

const onEmojiSelect = emoji => {
  // Tapping the same emoji we already sent toggles it off via the
  // server's mirror of WhatsApp behaviour; the backend handles that
  // decision, we just send the chosen emoji.
  store.dispatch('conversation/toggleReaction', {
    messageId: props.messageId,
    emoji,
  });
  closePicker();
};

const onChipClick = () => {
  if (!contactReaction.value) return;
  // Re-sending our active emoji removes it (backend toggle).
  store.dispatch('conversation/toggleReaction', {
    messageId: props.messageId,
    emoji: contactReaction.value,
  });
};
</script>

<template>
  <div class="reaction-wrap">
    <!-- Trigger button: only rendered when there is no active picker. -->
    <button
      v-if="!isPickerOpen"
      type="button"
      class="reaction-trigger"
      :aria-label="$t('REACTIONS.REACT_LABEL')"
      @click.stop="togglePicker"
    >
      <i class="i-lucide-smile-plus size-4" />
    </button>

    <!-- Inline picker popover with six quick emojis. -->
    <div
      v-if="isPickerOpen"
      v-on-clickaway="closePicker"
      class="reaction-picker"
      role="menu"
    >
      <button
        v-for="emoji in QUICK_EMOJIS"
        :key="emoji"
        type="button"
        class="reaction-emoji"
        :aria-label="emoji"
        @click.stop="onEmojiSelect(emoji)"
      >
        {{ emoji }}
      </button>
    </div>

    <!-- Active reaction chips. Up to two slots: the contact's own and
         the agent's. Tapping the contact chip removes it. -->
    <div v-if="contactReaction || agentReaction" class="reaction-chips">
      <button
        v-if="contactReaction"
        type="button"
        class="reaction-chip reaction-chip--contact"
        :aria-label="`Your reaction ${contactReaction}`"
        @click.stop="onChipClick"
      >
        {{ contactReaction }}
      </button>
      <span
        v-if="agentReaction"
        class="reaction-chip reaction-chip--agent"
        :aria-label="`Agent reaction ${agentReaction}`"
      >
        {{ agentReaction }}
      </span>
    </div>
  </div>
</template>

<style lang="scss" scoped>
.reaction-wrap {
  position: relative;
}

.reaction-trigger {
  position: absolute;
  top: -10px;
  right: -10px;
  width: 24px;
  height: 24px;
  border-radius: 9999px;
  background-color: #ffffff;
  box-shadow: 0 1px 2px rgba(11, 20, 26, 0.15);
  display: none;
  align-items: center;
  justify-content: center;
  color: #54656f;
  z-index: 2;
}

// Only reveal the trigger on hover of the parent bubble row, mirroring
// the WhatsApp Web pattern (a small face icon that pops above the
// bubble on hover). Touch devices will continue to see the chip-only
// view; a long-press affordance can land in a follow-up pass.
.chat-bubble-wrap:hover .reaction-trigger,
.user-message-wrap:hover .reaction-trigger,
.agent-message-wrap:hover .reaction-trigger {
  display: flex;
}

.reaction-picker {
  position: absolute;
  top: -38px;
  right: -8px;
  background-color: #ffffff;
  border-radius: 9999px;
  padding: 4px 6px;
  box-shadow: 0 4px 10px rgba(11, 20, 26, 0.18);
  display: inline-flex;
  align-items: center;
  gap: 2px;
  z-index: 3;

  .dark & {
    background-color: #1f2c34;
  }
}

.reaction-emoji {
  width: 28px;
  height: 28px;
  border-radius: 9999px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 1.05rem;
  transition: transform 0.1s ease-out;

  &:hover {
    transform: scale(1.2);
  }
}

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
