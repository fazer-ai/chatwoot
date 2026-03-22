<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  channel: { type: Object, required: true },
  currentUserId: { type: Number, required: true },
  isAdmin: { type: Boolean, default: false },
});

const emit = defineEmits([
  'close',
  'archive',
  'unarchive',
  'delete',
  'mute',
  'unmute',
  'favorite',
  'unfavorite',
]);

const { t } = useI18n();

const showDeleteConfirm = ref(false);

const members = computed(() => props.channel.members || []);

const isMuted = computed(() => props.channel.muted);
const isFavorited = computed(() => props.channel.favorited);
const isArchived = computed(() => props.channel.status === 'archived');

const channelTypeLabel = computed(() => {
  const type = props.channel.channel_type;
  if (type === 'dm') return t('INTERNAL_CHAT.DM.NEW');
  if (type === 'private_channel') return t('INTERNAL_CHAT.CHANNEL.PRIVATE');
  return t('INTERNAL_CHAT.CHANNEL.PUBLIC');
});

const channelTypeIcon = computed(() => {
  const type = props.channel.channel_type;
  if (type === 'dm') return 'i-lucide-message-circle';
  if (type === 'private_channel') return 'i-lucide-lock';
  return 'i-lucide-hash';
});

const createdAt = computed(() => {
  if (!props.channel.created_at) return '';
  return new Date(props.channel.created_at).toLocaleDateString();
});

function handleMuteToggle() {
  if (isMuted.value) {
    emit('unmute');
  } else {
    emit('mute');
  }
}

function handleFavoriteToggle() {
  if (isFavorited.value) {
    emit('unfavorite');
  } else {
    emit('favorite');
  }
}

function handleArchiveToggle() {
  if (isArchived.value) {
    emit('unarchive');
  } else {
    emit('archive');
  }
}

function handleDelete() {
  if (!showDeleteConfirm.value) {
    showDeleteConfirm.value = true;
    return;
  }
  emit('delete');
  showDeleteConfirm.value = false;
}
</script>

<template>
  <div class="flex h-full w-80 flex-col border-l border-n-slate-5 bg-n-solid-1">
    <div
      class="flex items-center justify-between border-b border-n-slate-5 px-4 py-3"
    >
      <h3 class="text-sm font-semibold text-n-slate-12">
        {{ t('INTERNAL_CHAT.CHANNEL.SETTINGS') }}
      </h3>
      <button
        class="flex items-center justify-center rounded p-1 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        @click="emit('close')"
      >
        <Icon icon="i-lucide-x" class="size-4" />
      </button>
    </div>

    <div class="flex-1 overflow-y-auto">
      <!-- Channel Info -->
      <div class="border-b border-n-slate-5 px-4 py-4">
        <h4 class="mb-3 text-xs font-semibold uppercase text-n-slate-10">
          {{ t('INTERNAL_CHAT.CHANNEL.INFO') }}
        </h4>
        <div class="space-y-2">
          <div class="flex items-center gap-2">
            <Icon :icon="channelTypeIcon" class="size-4 text-n-slate-10" />
            <span class="text-sm text-n-slate-12">
              {{ channel.name }}
            </span>
          </div>
          <div v-if="channel.description" class="text-sm text-n-slate-10">
            {{ channel.description }}
          </div>
          <div class="flex items-center gap-2 text-xs text-n-slate-10">
            <span>{{ channelTypeLabel }}</span>
            <span v-if="createdAt">
              &middot; {{ t('INTERNAL_CHAT.CHANNEL.CREATED_AT') }}
              {{ createdAt }}
            </span>
          </div>
        </div>
      </div>

      <!-- Members -->
      <div class="border-b border-n-slate-5 px-4 py-4">
        <h4 class="mb-3 text-xs font-semibold uppercase text-n-slate-10">
          {{ t('INTERNAL_CHAT.CHANNEL.MEMBERS') }}
          <span v-if="members.length" class="ml-1 text-n-slate-9">
            ({{ members.length }})
          </span>
        </h4>
        <div class="space-y-2">
          <div
            v-for="member in members"
            :key="member.user_id"
            class="flex items-center gap-2"
          >
            <Avatar
              :src="member.avatar_url"
              :name="member.name || ''"
              :size="24"
            />
            <span class="text-sm text-n-slate-12">
              {{ member.name }}
            </span>
            <span
              v-if="member.role === 'admin'"
              class="rounded bg-n-alpha-2 px-1.5 py-0.5 text-xs text-n-slate-10"
            >
              {{ t('INTERNAL_CHAT.CHANNEL.ADMIN') }}
            </span>
            <span
              v-if="member.user_id === currentUserId"
              class="text-xs text-n-slate-10"
            >
              {{ t('INTERNAL_CHAT.CHANNEL.YOU') }}
            </span>
          </div>
          <div v-if="members.length === 0" class="text-sm text-n-slate-10">
            {{ t('INTERNAL_CHAT.CHANNEL.NO_MEMBERS') }}
          </div>
        </div>
      </div>

      <!-- Actions -->
      <div class="px-4 py-4">
        <h4 class="mb-3 text-xs font-semibold uppercase text-n-slate-10">
          {{ t('INTERNAL_CHAT.CHANNEL.ACTIONS') }}
        </h4>
        <div class="space-y-1">
          <button
            class="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-2"
            @click="handleMuteToggle"
          >
            <Icon
              :icon="isMuted ? 'i-lucide-bell' : 'i-lucide-bell-off'"
              class="size-4 text-n-slate-11"
            />
            {{
              isMuted
                ? t('INTERNAL_CHAT.CHANNEL.UNMUTE')
                : t('INTERNAL_CHAT.CHANNEL.MUTE')
            }}
          </button>

          <button
            class="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-2"
            @click="handleFavoriteToggle"
          >
            <Icon
              :icon="isFavorited ? 'i-lucide-star-off' : 'i-lucide-star'"
              class="size-4 text-n-slate-11"
            />
            {{
              isFavorited
                ? t('INTERNAL_CHAT.CHANNEL.UNFAVORITE')
                : t('INTERNAL_CHAT.CHANNEL.FAVORITE')
            }}
          </button>

          <button
            v-if="isAdmin"
            class="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-2"
            @click="handleArchiveToggle"
          >
            <Icon
              :icon="
                isArchived ? 'i-lucide-archive-restore' : 'i-lucide-archive'
              "
              class="size-4 text-n-slate-11"
            />
            {{
              isArchived
                ? t('INTERNAL_CHAT.CHANNEL.UNARCHIVE')
                : t('INTERNAL_CHAT.CHANNEL.ARCHIVE')
            }}
          </button>

          <button
            v-if="isAdmin"
            class="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-n-ruby-11 hover:bg-n-ruby-3"
            @click="handleDelete"
          >
            <Icon icon="i-lucide-trash-2" class="size-4" />
            {{ t('INTERNAL_CHAT.CHANNEL.DELETE') }}
          </button>

          <div
            v-if="showDeleteConfirm"
            class="mt-2 rounded-lg border border-n-ruby-7 bg-n-ruby-2 p-3"
          >
            <p class="mb-2 text-sm text-n-ruby-11">
              {{ t('INTERNAL_CHAT.CHANNEL.CONFIRM_DELETE') }}
            </p>
            <div class="flex gap-2">
              <button
                class="rounded-lg bg-n-ruby-9 px-3 py-1.5 text-sm font-medium text-white hover:bg-n-ruby-10"
                @click="handleDelete"
              >
                {{ t('INTERNAL_CHAT.CHANNEL.DELETE') }}
              </button>
              <button
                class="rounded-lg px-3 py-1.5 text-sm text-n-slate-11 hover:bg-n-alpha-2"
                @click="showDeleteConfirm = false"
              >
                {{ t('INTERNAL_CHAT.POLL.CANCEL') }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
