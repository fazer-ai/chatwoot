<script setup>
import { computed } from 'vue';
import { IFrameHelper } from 'simulator/helpers/utils';
import { CHATWOOT_ON_START_CONVERSATION } from '../constants/sdkEvents';
import GroupedAvatars from 'simulator/components/GroupedAvatars.vue';
import { useAvailability } from 'simulator/composables/useAvailability';
import { useMapGetter } from 'dashboard/composables/store.js';
import { toRef } from 'vue';

const props = defineProps({
  availableAgents: { type: Array, default: () => [] },
  hasConversation: { type: Boolean, default: false },
});

const emit = defineEmits(['startConversation']);

const widgetColor = useMapGetter('appConfig/getWidgetColor');

const { isOnline } = useAvailability(toRef(props, 'availableAgents'));
const showAvatars = computed(
  () => isOnline.value && props.availableAgents.length
);

const startConversation = () => {
  emit('startConversation');
  if (!props.hasConversation) {
    IFrameHelper.sendMessage({
      event: 'onEvent',
      eventIdentifier: CHATWOOT_ON_START_CONVERSATION,
      data: { hasConversation: false },
    });
  }
};

// Reset the simulator session and reload the iframe so the next bootstrap
// provisions a fresh contact_inbox + conversation. Clearing both storages
// and the cookie jar is the cleanest way to wipe whatever the widget SDK
// persisted (auth token, cw_conversation, source_id).
const startFreshConversation = () => {
  try {
    window.localStorage?.clear();
    window.sessionStorage?.clear();
    document.cookie.split(';').forEach(rawCookie => {
      const name = rawCookie.split('=')[0].trim();
      if (!name) return;
      document.cookie = `${name}=;expires=${new Date(0).toUTCString()};path=/`;
    });
  } finally {
    window.location.reload();
  }
};
</script>

<template>
  <div
    class="flex flex-col gap-3 w-full shadow outline-1 outline outline-n-container rounded-xl bg-n-background dark:bg-n-solid-2 px-5 py-4"
  >
    <GroupedAvatars v-if="showAvatars" :users="availableAgents" />

    <div class="flex flex-col gap-2">
      <button
        class="inline-flex items-center gap-1 font-medium text-n-slate-12"
        :style="{ color: widgetColor }"
        @click="startConversation"
      >
        <span>
          {{
            hasConversation
              ? $t('CONTINUE_CONVERSATION')
              : $t('START_CONVERSATION')
          }}
        </span>
        <i class="i-lucide-chevron-right size-5 mt-px" />
      </button>
      <button
        v-if="hasConversation"
        class="inline-flex items-center gap-1 text-n-slate-11 hover:text-n-slate-12"
        @click="startFreshConversation"
      >
        <span>{{ $t('START_NEW_CONVERSATION') }}</span>
        <i class="i-lucide-rotate-cw size-4 mt-px" />
      </button>
    </div>
  </div>
</template>
