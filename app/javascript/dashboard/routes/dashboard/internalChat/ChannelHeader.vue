<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useMapGetter } from 'dashboard/composables/store';

const props = defineProps({
  channel: {
    type: Object,
    default: () => ({}),
  },
  pinnedMessages: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['settings', 'scrollToPinned']);

const { t } = useI18n();

const currentUser = useMapGetter('getCurrentUser');

const channelName = computed(() => {
  if (props.channel.channel_type === 'dm' && props.channel.members?.length) {
    const otherMember = props.channel.members.find(
      m => m.user_id !== currentUser.value?.id
    );
    return otherMember?.name || props.channel.name || 'Direct Message';
  }
  return props.channel.name || '';
});

const channelDescription = computed(() => {
  return props.channel.description || '';
});

const memberCount = computed(() => {
  return props.channel.members_count || 0;
});

const isDM = computed(() => {
  return props.channel.channel_type === 'dm';
});

const isArchived = computed(() => {
  return props.channel.status === 'archived';
});

const channelIcon = computed(() => {
  if (isDM.value) return 'i-lucide-message-circle';
  if (props.channel.channel_type === 'private_channel') return 'i-lucide-lock';
  return 'i-lucide-hash';
});

const pinnedContent = computed(() => {
  if (!props.pinnedMessages.length) return '';
  const content = props.pinnedMessages[0].content || '';
  return content.length > 100 ? `${content.substring(0, 100)}...` : content;
});

const pinnedCountLabel = computed(() => {
  if (props.pinnedMessages.length <= 1) return '';
  return `(${props.pinnedMessages.length})`;
});
</script>

<template>
  <div>
    <div
      class="flex items-center gap-3 border-b border-n-slate-5 bg-n-solid-2 px-4 py-3"
    >
      <div class="flex items-center gap-2 min-w-0 flex-1">
        <Icon
          :icon="channelIcon"
          class="size-5 text-n-slate-11 flex-shrink-0"
        />
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
          :title="t('INTERNAL_CHAT.CHANNEL.SETTINGS')"
          :aria-label="t('INTERNAL_CHAT.CHANNEL.SETTINGS')"
          @click="emit('settings')"
        >
          <Icon icon="i-lucide-settings" class="size-4" />
        </button>
      </div>
    </div>

    <!-- Pinned message banner -->
    <div
      v-if="pinnedMessages.length > 0"
      class="flex items-center gap-2 border-b border-n-slate-5 bg-n-amber-2 px-4 py-2 cursor-pointer hover:bg-n-amber-3 transition-colors"
      @click="emit('scrollToPinned', pinnedMessages[0])"
    >
      <Icon
        icon="i-lucide-pin"
        class="size-3.5 text-n-amber-11 flex-shrink-0"
      />
      <span class="text-xs font-medium text-n-amber-11">
        {{ t('INTERNAL_CHAT.PIN.PINNED_MESSAGE') }}
        <span v-if="pinnedCountLabel" class="ml-1">
          {{ pinnedCountLabel }}
        </span>
      </span>
      <span class="truncate text-xs text-n-slate-12">
        {{ pinnedContent }}
      </span>
    </div>
  </div>
</template>
