<script setup>
import { CSAT_RATINGS } from 'shared/constants/messages';

const props = defineProps({
  selectedRating: {
    type: Number,
    default: null,
  },
  isDisabled: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['selectRating']);

const ratings = CSAT_RATINGS;

// No scale on hover. A touch device keeps :hover on the last element touched, so an
// unselected face would stay enlarged and coloured, lying about the state. Selection alone
// carries the emphasis now.
const buttonClass = rating => [
  'flex h-12 w-12 items-center justify-center rounded-full text-3xl transition',
  'sm:h-14 sm:w-14 sm:text-4xl',
  'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2',
  'focus-visible:ring-[color:var(--survey-brand)]',
  'disabled:cursor-default disabled:opacity-50',
  rating.value === props.selectedRating
    ? 'grayscale-0 bg-n-slate-3 ring-2 ring-[color:var(--survey-brand)]'
    : 'grayscale enabled:hover:grayscale-0',
];
</script>

<template>
  <div class="flex flex-wrap gap-2 py-4 sm:gap-3">
    <button
      v-for="rating in ratings"
      :key="rating.key"
      type="button"
      :disabled="isDisabled"
      :aria-label="$t(rating.translationKey)"
      :aria-pressed="rating.value === selectedRating"
      :class="buttonClass(rating)"
      @click="emit('selectRating', rating.value)"
    >
      <!-- The label above already says "Good"; without this a screen reader would read the
           glyph name on top of it. -->
      <span aria-hidden="true">{{ rating.emoji }}</span>
    </button>
  </div>
</template>
