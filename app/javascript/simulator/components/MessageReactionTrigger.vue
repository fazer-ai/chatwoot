<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';

const props = defineProps({
  messageId: { type: Number, required: true },
  // Drives where the inline picker pops up relative to the trigger.
  // For outgoing (user-side) bubbles the trigger sits to the *left*
  // of the bubble, so the popover should grow to the left.
  alignment: {
    type: String,
    default: 'right',
    validator: value => ['right', 'left'].includes(value),
  },
});

const store = useStore();
const isPickerOpen = ref(false);

const QUICK_EMOJIS = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

const reactionsByMessageId = computed(
  () => store.getters['conversation/getReactionsByMessageId'] || {}
);
const contactReaction = computed(
  () => reactionsByMessageId.value[props.messageId]?.contact?.emoji || ''
);

const togglePicker = () => {
  isPickerOpen.value = !isPickerOpen.value;
};
const closePicker = () => {
  isPickerOpen.value = false;
};

const onEmojiSelect = emoji => {
  // Re-sending the active emoji removes it on the backend (WhatsApp
  // toggle semantics), so we just forward the choice and let the
  // server decide.
  store.dispatch('conversation/toggleReaction', {
    messageId: props.messageId,
    emoji,
  });
  closePicker();
};
</script>

<template>
  <div class="reaction-trigger-wrap">
    <button
      type="button"
      class="reaction-trigger"
      :class="{ 'reaction-trigger--active': !!contactReaction }"
      :aria-label="$t('REACTIONS.REACT_LABEL')"
      @click.stop="togglePicker"
    >
      <i class="i-lucide-smile-plus size-4" />
    </button>

    <div
      v-if="isPickerOpen"
      v-on-clickaway="closePicker"
      class="reaction-picker"
      :class="`reaction-picker--${alignment}`"
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
  </div>
</template>

<style lang="scss" scoped>
.reaction-trigger-wrap {
  position: relative;
  display: inline-flex;
}

.reaction-trigger {
  width: 28px;
  height: 28px;
  border-radius: 9999px;
  background-color: #ffffff;
  box-shadow: 0 1px 2px rgba(11, 20, 26, 0.15);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  color: #54656f;

  &:hover {
    background-color: #f0f2f5;
  }

  &--active {
    color: #008069;
  }

  .dark & {
    background-color: #1f2c34;
    color: #aebac1;

    &:hover {
      background-color: #2a3942;
    }
  }
}

.reaction-picker {
  position: absolute;
  top: -38px;
  background-color: #ffffff;
  border-radius: 9999px;
  padding: 4px 6px;
  box-shadow: 0 4px 10px rgba(11, 20, 26, 0.18);
  display: inline-flex;
  align-items: center;
  gap: 2px;
  z-index: 3;

  &--right {
    left: 0;
  }

  &--left {
    right: 0;
  }

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
</style>
