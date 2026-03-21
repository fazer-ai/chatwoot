<script setup>
import { onMounted, computed } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
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

onMounted(() => {
  fetchChannels();
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
      <div v-else class="flex h-full items-center justify-center bg-n-solid-1">
        <div class="text-center">
          <p class="text-sm text-n-slate-10">
            {{ t('INTERNAL_CHAT.CHANNEL.NO_MESSAGES') }}
          </p>
        </div>
      </div>
    </div>
  </div>
</template>
