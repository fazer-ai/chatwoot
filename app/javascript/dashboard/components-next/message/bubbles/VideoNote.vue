<script setup>
import { ref, computed, onMounted } from 'vue';
import BaseBubble from './Base.vue';
import Icon from 'next/icon/Icon.vue';
import { useLoadWithRetry } from 'dashboard/composables/loadWithRetry';
import { useMessageContext } from '../provider.js';
import { MESSAGE_VARIANTS } from '../constants';

// WhatsApp's video note: recorded square and played in a circle, with no frame around
// it. A click plays it with sound and pauses it, as on the phone.
const { attachments, variant } = useMessageContext();

// No bubble behind the circle, except on a private note: the amber is what marks it as
// internal, as on the audio bubble.
const isPrivate = computed(() => variant.value === MESSAGE_VARIANTS.PRIVATE);

const attachment = computed(() => attachments.value[0]);
const player = ref(null);
const isPlaying = ref(false);

const { isLoaded, hasError, loadWithRetry } = useLoadWithRetry({
  type: 'video',
});

onMounted(() => {
  if (attachment.value?.dataUrl) {
    loadWithRetry(attachment.value.dataUrl);
  }
});

const togglePlayback = () => {
  if (!player.value) return;

  if (player.value.paused) {
    // A pause before playback starts aborts the request, and a browser that refuses it
    // fires no error event. Either way the note is not playing, and the play icon stays.
    player.value.play().catch(() => {
      isPlaying.value = false;
    });
  } else {
    player.value.pause();
  }
};

const handleError = () => {
  hasError.value = true;
};
</script>

<template>
  <BaseBubble
    :class="isPrivate ? 'p-2' : 'bg-transparent'"
    data-bubble-name="video-note"
  >
    <div
      v-if="hasError"
      class="flex items-center gap-1 p-3 text-center rounded-lg bg-n-slate-4"
    >
      <Icon icon="i-lucide-circle-off" class="text-n-slate-11" />
      <p class="mb-0 text-n-slate-11">
        {{ $t('COMPONENTS.MEDIA.VIDEO_UNAVAILABLE') }}
      </p>
    </div>
    <button
      v-else-if="isLoaded"
      type="button"
      :aria-label="
        isPlaying
          ? $t('COMPONENTS.MEDIA.PAUSE_VIDEO_NOTE')
          : $t('COMPONENTS.MEDIA.PLAY_VIDEO_NOTE')
      "
      class="relative block p-0 overflow-hidden border-0 rounded-full size-60 bg-n-slate-4"
      @click="togglePlayback"
    >
      <video
        ref="player"
        class="object-cover size-full"
        :src="attachment.dataUrl"
        playsinline
        @play="isPlaying = true"
        @pause="isPlaying = false"
        @ended="isPlaying = false"
        @error="handleError"
      />
      <span
        v-if="!isPlaying"
        class="absolute inset-0 flex items-center justify-center pointer-events-none"
      >
        <span
          class="flex items-center justify-center rounded-full size-12 bg-n-alpha-black1 backdrop-blur-sm"
        >
          <Icon icon="i-lucide-play" class="text-white size-6" />
        </span>
      </span>
    </button>
  </BaseBubble>
</template>
