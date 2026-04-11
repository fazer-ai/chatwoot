<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import NextSelect from 'dashboard/components-next/select/Select.vue';
import ProFeatureNudge from './ProFeatureNudge.vue';
import { useInternalChatPro } from 'dashboard/composables/useInternalChatPro';

const store = useStore();
const { t } = useI18n();
const { maxPrivateChannels } = useInternalChatPro();

const dialogRef = ref(null);
const channelName = ref('');
const channelDescription = ref('');
const channelType = ref('public_channel');
const categoryId = ref('');
const isCreating = ref(false);
const selectedAgentIds = ref([]);
const memberSearchQuery = ref('');

const categories = computed(
  () => store.getters['internalChat/getCategories'] || []
);

const currentUserId = computed(() => store.getters.getCurrentUser?.id);

const agents = computed(() => {
  const allAgents = store.getters['agents/getAgents'] || [];
  return allAgents.filter(agent => agent.id !== currentUserId.value);
});

const filteredAgents = computed(() => {
  if (!memberSearchQuery.value) return agents.value;
  const query = memberSearchQuery.value.toLowerCase();
  return agents.value.filter(agent =>
    (agent.name || '').toLowerCase().includes(query)
  );
});

const isPrivate = computed({
  get: () => channelType.value === 'private_channel',
  set: val => {
    channelType.value = val ? 'private_channel' : 'public_channel';
  },
});

const privateChannelCount = computed(() => {
  const channels = store.getters['internalChat/getChannels'] || [];
  return channels.filter(
    c => c.channel_type === 'private_channel' && c.status !== 'archived'
  ).length;
});

const canCreatePrivate = computed(() => {
  if (!maxPrivateChannels.value) return true;
  return privateChannelCount.value < maxPrivateChannels.value;
});

const privateLimitReached = computed(
  () => isPrivate.value && !canCreatePrivate.value
);

const categoryOptions = computed(() => [
  { value: '', label: t('INTERNAL_CHAT.CATEGORY.NONE') },
  ...categories.value.map(cat => ({ value: cat.id, label: cat.name })),
]);

const isFormValid = computed(
  () => channelName.value.trim().length > 0 && !privateLimitReached.value
);

function toggleAgent(agentId) {
  const idx = selectedAgentIds.value.indexOf(agentId);
  if (idx === -1) {
    selectedAgentIds.value.push(agentId);
  } else {
    selectedAgentIds.value.splice(idx, 1);
  }
}

function open() {
  channelName.value = '';
  channelDescription.value = '';
  channelType.value = 'public_channel';
  categoryId.value = '';
  selectedAgentIds.value = [];
  memberSearchQuery.value = '';
  store.dispatch('agents/get');
  dialogRef.value?.open();
}

async function handleConfirm() {
  if (!isFormValid.value) return;

  isCreating.value = true;
  try {
    await store.dispatch('internalChat/create', {
      channel: {
        name: channelName.value.trim(),
        description: channelDescription.value.trim(),
        channel_type: channelType.value,
        category_id: categoryId.value || null,
      },
      member_ids: isPrivate.value ? selectedAgentIds.value : [],
    });
    useAlert(t('INTERNAL_CHAT.CHANNEL.CREATED'));
    dialogRef.value?.close();
  } catch (error) {
    if (error?.response?.status === 402) {
      // Backend rejected: private channel limit reached. Refresh UI state.
      channelType.value = 'public_channel';
    }
  } finally {
    isCreating.value = false;
  }
}

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('INTERNAL_CHAT.NEW_CHANNEL')"
    :confirm-button-label="t('INTERNAL_CHAT.NEW_CHANNEL')"
    :disable-confirm-button="!isFormValid"
    :is-loading="isCreating"
    @confirm="handleConfirm"
  >
    <div class="flex flex-col gap-4">
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('INTERNAL_CHAT.CHANNEL.NAME') }}
        </label>
        <input
          v-model="channelName"
          type="text"
          class="w-full rounded-lg border border-n-slate-6 bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 placeholder-n-slate-10 outline-none focus:border-n-brand"
          :placeholder="t('INTERNAL_CHAT.CHANNEL.NAME')"
        />
      </div>
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('INTERNAL_CHAT.CHANNEL.DESCRIPTION') }}
        </label>
        <textarea
          v-model="channelDescription"
          rows="3"
          class="w-full rounded-lg border border-n-slate-6 bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 placeholder-n-slate-10 outline-none focus:border-n-brand resize-none"
          :placeholder="t('INTERNAL_CHAT.CHANNEL.DESCRIPTION')"
        />
      </div>
      <div v-if="categories.length > 0" class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('INTERNAL_CHAT.CATEGORY.NAME') }}
        </label>
        <NextSelect
          v-model="categoryId"
          class="w-full"
          :options="categoryOptions"
          :placeholder="t('INTERNAL_CHAT.CATEGORY.NONE')"
        />
      </div>
      <label class="flex cursor-pointer items-center justify-between">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('INTERNAL_CHAT.CHANNEL.PRIVATE') }}
        </span>
        <Switch v-model="isPrivate" />
      </label>

      <!-- Public channel info note -->
      <div
        v-if="!isPrivate"
        class="rounded-lg bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-10"
      >
        {{ t('INTERNAL_CHAT.CHANNEL.ALL_AGENTS_NOTE') }}
      </div>

      <!-- Private channel limit reached -->
      <ProFeatureNudge
        v-if="privateLimitReached"
        feature="private_channels"
        inline
      />

      <!-- Private channel: agent selection -->
      <template v-if="isPrivate && canCreatePrivate">
        <!-- Agent selection -->
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('INTERNAL_CHAT.CHANNEL.SELECT_AGENTS') }}
          </label>
          <input
            v-model="memberSearchQuery"
            type="text"
            class="w-full rounded-lg border border-n-slate-6 bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 placeholder-n-slate-10 outline-none focus:border-n-brand"
            :placeholder="t('INTERNAL_CHAT.DM.SELECT_AGENTS')"
          />
          <div
            class="flex max-h-48 flex-col gap-1 overflow-y-auto rounded-lg border border-n-slate-6 p-2"
          >
            <label
              v-for="agent in filteredAgents"
              :key="agent.id"
              class="flex cursor-pointer items-center gap-2 rounded px-2 py-1.5 text-sm text-n-slate-12 hover:bg-n-alpha-1"
            >
              <input
                type="checkbox"
                :checked="selectedAgentIds.includes(agent.id)"
                class="rounded border-n-slate-6"
                @change="toggleAgent(agent.id)"
              />
              <Avatar
                :name="agent.name || ''"
                :src="agent.thumbnail || ''"
                :size="24"
                rounded-full
              />
              <span class="truncate">{{ agent.name }}</span>
            </label>
            <p
              v-if="filteredAgents.length === 0"
              class="px-2 py-3 text-center text-sm text-n-slate-10"
            >
              {{ t('INTERNAL_CHAT.DM.SELECT_AGENTS') }}
            </p>
          </div>
        </div>
      </template>
    </div>
  </Dialog>
</template>
