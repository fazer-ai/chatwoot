<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { useEventListener } from '@vueuse/core';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import EmojiInput from 'shared/components/emoji/EmojiInput.vue';

defineProps({
  alignment: {
    type: String,
    default: 'right',
    validator: value => ['left', 'right'].includes(value),
  },
  currentUserEmoji: {
    type: String,
    default: null,
  },
});

const emit = defineEmits(['select']);

const { t } = useI18n();

const QUICK_EMOJIS = [
  { emoji: '👍', labelKey: 'CONVERSATION.REACTIONS.QUICK.THUMBS_UP' },
  { emoji: '❤️', labelKey: 'CONVERSATION.REACTIONS.QUICK.HEART' },
  { emoji: '😂', labelKey: 'CONVERSATION.REACTIONS.QUICK.JOY' },
  { emoji: '😮', labelKey: 'CONVERSATION.REACTIONS.QUICK.SURPRISED' },
  { emoji: '😢', labelKey: 'CONVERSATION.REACTIONS.QUICK.SAD' },
  { emoji: '🙏', labelKey: 'CONVERSATION.REACTIONS.QUICK.PRAY' },
  { emoji: '🔥', labelKey: 'CONVERSATION.REACTIONS.QUICK.FIRE' },
  { emoji: '🎉', labelKey: 'CONVERSATION.REACTIONS.QUICK.PARTY' },
];

const isOpen = ref(false);
const showFullPicker = ref(false);

function close() {
  isOpen.value = false;
  showFullPicker.value = false;
}

function toggle() {
  if (isOpen.value) {
    close();
  } else {
    isOpen.value = true;
  }
}

function pickEmoji(emoji) {
  if (!emoji) return;
  emit('select', emoji);
  close();
}

function openFullPicker() {
  showFullPicker.value = true;
}

// Switching apps / Alt-Tab fires window blur but not a click event, so
// vOnClickOutside cannot reach it. Without this the picker stays open in
// the background and reappears on next hover.
useEventListener(window, 'blur', close);
</script>

<template>
  <div v-on-click-outside="close" class="relative">
    <button
      type="button"
      class="flex items-center justify-center rounded-full p-1 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
      :title="t('CONVERSATION.REACTIONS.ADD_REACTION')"
      :aria-label="t('CONVERSATION.REACTIONS.ADD_REACTION')"
      @click="toggle"
    >
      <Icon icon="i-lucide-smile-plus" class="size-4" />
    </button>
    <div
      v-if="isOpen && !showFullPicker"
      class="absolute bottom-[calc(100%+0.5rem)] z-50 flex w-max items-center gap-1 rounded-full border border-n-slate-6 bg-n-solid-2 p-1 shadow-lg"
      :class="
        alignment === 'right' ? '-right-1 left-auto' : '-left-1 right-auto'
      "
    >
      <button
        v-for="item in QUICK_EMOJIS"
        :key="item.labelKey"
        type="button"
        class="flex size-7 items-center justify-center rounded-full text-base hover:bg-n-alpha-2"
        :class="{
          'ring-2 ring-n-brand bg-n-alpha-2': item.emoji === currentUserEmoji,
        }"
        :title="
          item.emoji === currentUserEmoji
            ? t('CONVERSATION.REACTIONS.CLICK_TO_REMOVE')
            : t(item.labelKey)
        "
        :aria-label="
          item.emoji === currentUserEmoji
            ? t('CONVERSATION.REACTIONS.CLICK_TO_REMOVE')
            : t(item.labelKey)
        "
        :aria-pressed="item.emoji === currentUserEmoji"
        @click="pickEmoji(item.emoji)"
      >
        {{ item.emoji }}
      </button>
      <button
        type="button"
        class="flex size-7 items-center justify-center rounded-full text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :title="t('CONVERSATION.REACTIONS.MORE_EMOJIS')"
        :aria-label="t('CONVERSATION.REACTIONS.MORE_EMOJIS')"
        @click="openFullPicker"
      >
        <Icon icon="i-lucide-plus" class="size-4" />
      </button>
    </div>
    <EmojiInput
      v-if="isOpen && showFullPicker"
      class="!bottom-[calc(100%+1.25rem)] !top-auto"
      :class="
        alignment === 'right' ? '!right-0 !left-auto' : '!left-0 !right-auto'
      "
      :on-click="pickEmoji"
    />
  </div>
</template>
