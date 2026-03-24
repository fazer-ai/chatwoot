<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import InternalChatChannelsAPI from 'dashboard/api/internalChatChannels';

const props = defineProps({
  channelId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['updated']);

const store = useStore();
const { t } = useI18n();

const dialogRef = ref(null);
const memberUserIds = ref(new Set());
const searchQuery = ref('');
const isLoading = ref(false);
const isSaving = ref(false);
const originalMemberIds = ref(new Set());
// Maps user_id -> member record id (needed for removeMember API)
const memberRecordMap = ref(new Map());

const currentUserId = computed(() => store.getters.getCurrentUser?.id);

const allAgents = computed(() => {
  const agents = store.getters['agents/getAgents'] || [];
  return agents.filter(a => a.id !== currentUserId.value);
});

const filteredAgents = computed(() => {
  if (!searchQuery.value) return allAgents.value;
  const query = searchQuery.value.toLowerCase();
  return allAgents.value.filter(a =>
    (a.name || '').toLowerCase().includes(query)
  );
});

async function fetchMembers() {
  isLoading.value = true;
  try {
    const { data } = await InternalChatChannelsAPI.getMembers(props.channelId);
    const ids = new Set(data.map(m => m.user_id));
    const recordMap = new Map();
    data.forEach(m => recordMap.set(m.user_id, m.id));
    memberUserIds.value = ids;
    originalMemberIds.value = new Set(ids);
    memberRecordMap.value = recordMap;
  } catch {
    // silently handle
  } finally {
    isLoading.value = false;
  }
}

function toggleAgent(agentId) {
  const ids = new Set(memberUserIds.value);
  if (ids.has(agentId)) {
    ids.delete(agentId);
  } else {
    ids.add(agentId);
  }
  memberUserIds.value = ids;
}

async function handleConfirm() {
  const toAdd = [...memberUserIds.value].filter(
    id => !originalMemberIds.value.has(id)
  );
  const toRemove = [...originalMemberIds.value].filter(
    id => !memberUserIds.value.has(id)
  );

  if (toAdd.length === 0 && toRemove.length === 0) {
    dialogRef.value?.close();
    return;
  }

  isSaving.value = true;
  try {
    // Serialize to avoid race conditions with ActionCable broadcasts
    const addChain = toAdd.reduce(
      (p, id) =>
        p.then(() => InternalChatChannelsAPI.addMember(props.channelId, id)),
      Promise.resolve()
    );
    await addChain;

    const removeChain = toRemove.reduce((p, userId) => {
      const memberId = memberRecordMap.value.get(userId);
      return memberId
        ? p.then(() =>
            InternalChatChannelsAPI.removeMember(props.channelId, memberId)
          )
        : p;
    }, Promise.resolve());
    await removeChain;
  } finally {
    isSaving.value = false;
    dialogRef.value?.close();
    emit('updated');
  }
}

function open() {
  searchQuery.value = '';
  store.dispatch('agents/get');
  fetchMembers();
  dialogRef.value?.open();
}

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('INTERNAL_CHAT.CHANNEL.EDIT_MEMBERS')"
    :confirm-button-label="t('INTERNAL_CHAT.CHANNEL.SAVE_MEMBERS')"
    :is-loading="isSaving"
    @confirm="handleConfirm"
  >
    <div class="flex flex-col gap-3">
      <input
        v-model="searchQuery"
        type="text"
        class="w-full rounded-lg border border-n-slate-6 bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 placeholder-n-slate-10 outline-none focus:border-n-brand"
        :placeholder="t('INTERNAL_CHAT.DM.SELECT_AGENTS')"
      />
      <div
        class="flex max-h-64 flex-col gap-1 overflow-y-auto rounded-lg border border-n-slate-6 p-2"
      >
        <label
          v-for="agent in filteredAgents"
          :key="agent.id"
          class="flex cursor-pointer items-center gap-2 rounded px-2 py-1.5 text-sm text-n-slate-12 hover:bg-n-alpha-1"
        >
          <input
            type="checkbox"
            :checked="memberUserIds.has(agent.id)"
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
  </Dialog>
</template>
