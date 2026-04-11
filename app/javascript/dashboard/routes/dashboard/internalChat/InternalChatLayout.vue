<script setup>
import { onMounted, computed } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ChannelSidebar from './ChannelSidebar.vue';
import ChannelView from './ChannelView.vue';

const store = useStore();
const route = useRoute();
const { t } = useI18n();

const activeChannelId = computed(() => {
  return Number(route.params.channelId) || null;
});

const activeChannel = computed(() => {
  if (!activeChannelId.value) return null;
  return store.getters['internalChat/getChannelById'](activeChannelId.value);
});

const isDraftsRoute = computed(() => {
  return route.name === 'internal_chat_drafts';
});

async function fetchChannels() {
  try {
    await store.dispatch('internalChat/get');
  } catch {
    useAlert(t('INTERNAL_CHAT.ERRORS.FETCH_CHANNELS'));
  }
}

onMounted(async () => {
  await fetchChannels();
  // If navigated directly to a channel not in the store (e.g. archived), fetch it
  if (activeChannelId.value && !activeChannel.value) {
    store.dispatch('internalChat/show', activeChannelId.value).catch(() => {});
  }
  store.dispatch('agents/get');
  store.dispatch('teams/get');
});
</script>

<template>
  <div class="flex h-full w-full">
    <ChannelSidebar />
    <div class="flex-1 min-w-0">
      <ChannelView
        v-if="activeChannelId && activeChannel"
        :key="activeChannelId"
        :channel-id="activeChannelId"
      />
      <router-view v-else-if="isDraftsRoute" />
      <div
        v-else
        class="flex h-full flex-col items-center justify-center gap-2 bg-n-solid-1"
      >
        <Icon icon="i-lucide-messages-square" class="size-10 text-n-slate-8" />
        <p class="text-sm font-medium text-n-slate-12">
          {{ t('INTERNAL_CHAT.EMPTY_STATE.TITLE') }}
        </p>
        <p class="text-xs text-n-slate-10">
          {{ t('INTERNAL_CHAT.EMPTY_STATE.SUBTITLE') }}
        </p>
      </div>
    </div>
  </div>
</template>
