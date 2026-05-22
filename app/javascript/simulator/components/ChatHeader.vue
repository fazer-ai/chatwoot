<script setup>
import { toRef } from 'vue';
import { useRouter } from 'vue-router';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';
import HeaderActions from './HeaderActions.vue';
import AvailabilityContainer from 'simulator/components/Availability/AvailabilityContainer.vue';
import { useAvailability } from 'simulator/composables/useAvailability';

const props = defineProps({
  avatarUrl: { type: String, default: '' },
  title: { type: String, default: '' },
  showPopoutButton: { type: Boolean, default: false },
  showBackButton: { type: Boolean, default: false },
  availableAgents: { type: Array, default: () => [] },
});

const availableAgents = toRef(props, 'availableAgents');

const router = useRouter();
const { isOnline } = useAvailability(availableAgents);

const onBackButtonClick = () => {
  router.replace({ name: 'home' });
};
</script>

<template>
  <header class="chat-header flex justify-between w-full px-4 py-3 gap-2">
    <div class="flex items-center">
      <button
        v-if="showBackButton"
        class="px-2 ltr:-ml-3 rtl:-mr-3"
        @click="onBackButtonClick"
      >
        <FluentIcon icon="chevron-left" size="24" class="text-white" />
      </button>
      <img
        v-if="avatarUrl"
        class="w-10 h-10 ltr:mr-3 rtl:ml-3 rounded-full object-cover"
        :src="avatarUrl"
        alt="avatar"
      />
      <div
        v-else
        class="initial-avatar w-10 h-10 ltr:mr-3 rtl:ml-3 rounded-full flex items-center justify-center text-sm font-semibold"
      >
        {{ (title || '?').charAt(0).toUpperCase() }}
      </div>
      <div class="flex flex-col gap-0.5">
        <div
          class="flex items-center text-base font-medium leading-tight text-white"
        >
          <span v-dompurify-html="title" class="ltr:mr-1 rtl:ml-1" />
          <div
            :class="`h-2 w-2 rounded-full
              ${isOnline ? 'bg-emerald-300' : 'hidden'}`"
          />
        </div>
        <AvailabilityContainer
          :agents="availableAgents"
          :show-header="false"
          :show-avatars="false"
          text-classes="header-availability-text text-xs leading-3"
        />
      </div>
    </div>
    <HeaderActions :show-popout-button="showPopoutButton" />
  </header>
</template>

<style lang="scss" scoped>
.chat-header {
  background-color: #008069;
  color: #ffffff;

  :deep(button) {
    color: #ffffff;
  }

  // The shared AvailabilityText baked in `text-n-slate-11` on its root
  // <span>; overriding via a Tailwind class on the prop loses the
  // specificity battle in dev (JIT scan misses `!text-white`). Pin it
  // with a deep selector here so the subtitle is always solid white.
  :deep(.header-availability-text),
  :deep(.header-availability-text span) {
    color: #ffffff !important;
  }
}

// Light-green pill behind the title initial when the inbox has no avatar
// configured. Mirrors WhatsApp Business' default avatar treatment.
.initial-avatar {
  background-color: #dcf8c6;
  color: #075e54;
}

:root[data-theme='dark'] .chat-header,
.dark .chat-header {
  background-color: #1f2c34;
}

:root[data-theme='dark'] .initial-avatar,
.dark .initial-avatar {
  background-color: #2a3942;
  color: #d1d7db;
}
</style>
