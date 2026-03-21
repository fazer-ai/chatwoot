<script setup>
import { ref } from 'vue';
import { vOnClickOutside } from '@vueuse/components';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const emit = defineEmits(['select', 'close']);

const QUICK_EMOJIS = [
  { emoji: '\uD83D\uDC4D', label: 'thumbs up' },
  { emoji: '\u2764\uFE0F', label: 'heart' },
  { emoji: '\uD83D\uDE02', label: 'joy' },
  { emoji: '\uD83D\uDE2E', label: 'surprised' },
  { emoji: '\uD83D\uDE22', label: 'sad' },
  { emoji: '\uD83D\uDE4F', label: 'pray' },
  { emoji: '\uD83D\uDD25', label: 'fire' },
  { emoji: '\uD83C\uDF89', label: 'party' },
];

const isOpen = ref(false);

function toggle() {
  isOpen.value = !isOpen.value;
}

function selectEmoji(emoji) {
  emit('select', emoji);
  isOpen.value = false;
}

function close() {
  isOpen.value = false;
  emit('close');
}
</script>

<template>
  <div class="relative">
    <button
      class="flex items-center justify-center rounded p-1 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
      @click="toggle"
    >
      <Icon icon="i-lucide-smile-plus" class="size-4" />
    </button>
    <div
      v-if="isOpen"
      v-on-click-outside="close"
      class="absolute bottom-full left-0 z-50 mb-1 flex items-center gap-1 rounded-lg border border-n-slate-6 bg-n-solid-2 p-2 shadow-lg"
    >
      <button
        v-for="item in QUICK_EMOJIS"
        :key="item.label"
        class="flex items-center justify-center rounded p-1 text-base hover:bg-n-alpha-2"
        :title="item.label"
        @click="selectEmoji(item.emoji)"
      >
        {{ item.emoji }}
      </button>
    </div>
  </div>
</template>
