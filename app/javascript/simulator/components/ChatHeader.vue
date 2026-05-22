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
        class="w-10 h-10 ltr:mr-3 rtl:ml-3 rounded-full flex items-center justify-center text-white text-sm font-semibold bg-white/20"
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
          text-classes="!text-white text-xs leading-3"
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
}

:root[data-theme='dark'] .chat-header,
.dark .chat-header {
  background-color: #1f2c34;
}
</style>
