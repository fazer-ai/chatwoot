<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  channel: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['settings']);

const { t } = useI18n();

const channelName = computed(() => {
  return props.channel.name || '';
});

const channelDescription = computed(() => {
  return props.channel.description || '';
});

const memberCount = computed(() => {
  return props.channel.members_count || 0;
});

const isDM = computed(() => {
  return props.channel.is_dm;
});

const isArchived = computed(() => {
  return props.channel.archived;
});

const channelIcon = computed(() => {
  if (isDM.value) return 'i-lucide-message-circle';
  if (props.channel.channel_type === 'private') return 'i-lucide-lock';
  return 'i-lucide-hash';
});
</script>

<template>
  <div
    class="flex items-center gap-3 border-b border-n-slate-5 bg-n-solid-2 px-4 py-3"
  >
    <div class="flex items-center gap-2 min-w-0 flex-1">
      <Icon :icon="channelIcon" class="size-5 text-n-slate-11 flex-shrink-0" />
      <div class="min-w-0 flex-1">
        <div class="flex items-center gap-2">
          <h2 class="truncate text-sm font-semibold text-n-slate-12">
            {{ channelName }}
          </h2>
          <span
            v-if="isArchived"
            class="flex-shrink-0 rounded bg-n-slate-4 px-1.5 py-0.5 text-xs text-n-slate-10"
          >
            {{ t('INTERNAL_CHAT.CHANNEL.ARCHIVED') }}
          </span>
        </div>
        <p v-if="channelDescription" class="truncate text-xs text-n-slate-10">
          {{ channelDescription }}
        </p>
      </div>
    </div>
    <div class="flex items-center gap-2 flex-shrink-0">
      <span
        v-if="memberCount > 0"
        class="flex items-center gap-1 text-xs text-n-slate-10"
      >
        <Icon icon="i-lucide-users" class="size-3.5" />
        {{ memberCount }}
      </span>
      <button
        class="flex items-center justify-center rounded-lg p-1.5 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 transition-colors"
        @click="emit('settings')"
      >
        <Icon icon="i-lucide-settings" class="size-4" />
      </button>
    </div>
  </div>
</template>
