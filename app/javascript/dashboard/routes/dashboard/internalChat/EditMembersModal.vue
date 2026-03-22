<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
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
const members = ref([]);
const searchQuery = ref('');
const isLoading = ref(false);

const currentUserId = computed(() => store.getters.getCurrentUser?.id);

const allAgents = computed(
  () => store.getters['agents/getVerifiedAgents'] || []
);

const nonMemberAgents = computed(() => {
  const memberIds = new Set(members.value.map(m => m.user_id));
  return allAgents.value
    .filter(a => !memberIds.has(a.id))
    .filter(a => {
      if (!searchQuery.value) return true;
      return (a.name || '')
        .toLowerCase()
        .includes(searchQuery.value.toLowerCase());
    });
});

async function fetchMembers() {
  isLoading.value = true;
  try {
    const { data } = await InternalChatChannelsAPI.getMembers(props.channelId);
    members.value = data;
  } catch {
    // silently handle
  } finally {
    isLoading.value = false;
  }
}

async function addMember(userId) {
  try {
    await InternalChatChannelsAPI.addMember(props.channelId, userId);
    fetchMembers();
    emit('updated');
  } catch {
    // silently handle
  }
}

async function removeMember(memberId) {
  try {
    await InternalChatChannelsAPI.removeMember(props.channelId, memberId);
    fetchMembers();
    emit('updated');
  } catch {
    // silently handle
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
    :show-confirm-button="false"
  >
    <div class="flex flex-col gap-3">
      <!-- Search to add -->
      <div>
        <input
          v-model="searchQuery"
          type="text"
          class="w-full rounded-lg border border-n-slate-6 bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 placeholder-n-slate-10 outline-none focus:border-n-brand"
          :placeholder="t('INTERNAL_CHAT.CHANNEL.ADD_MEMBER')"
        />
      </div>

      <!-- Agents to add -->
      <div
        v-if="searchQuery && nonMemberAgents.length"
        class="max-h-32 overflow-y-auto rounded-lg border border-n-slate-6"
      >
        <button
          v-for="agent in nonMemberAgents"
          :key="agent.id"
          type="button"
          class="flex w-full items-center gap-2 px-3 py-1.5 text-sm text-n-slate-12 hover:bg-n-alpha-1"
          @click="addMember(agent.id)"
        >
          <Avatar
            :name="agent.name || ''"
            :src="agent.thumbnail || ''"
            :size="24"
          />
          <span class="truncate">{{ agent.name }}</span>
          <Icon icon="i-lucide-plus" class="ml-auto size-3.5 text-n-slate-10" />
        </button>
      </div>

      <!-- Current members -->
      <div class="space-y-1">
        <div
          v-for="member in members"
          :key="member.user_id"
          class="flex items-center gap-2 rounded-lg px-2 py-1.5"
        >
          <Avatar
            :name="member.name || ''"
            :src="member.avatar_url || ''"
            :size="28"
          />
          <div class="flex-1 min-w-0">
            <span class="truncate text-sm text-n-slate-12">{{
              member.name
            }}</span>
            <span
              v-if="member.role === 'admin'"
              class="ml-1.5 rounded bg-n-alpha-2 px-1 py-0.5 text-[10px] text-n-slate-10"
            >
              {{ t('INTERNAL_CHAT.CHANNEL.ADMIN') }}
            </span>
          </div>
          <button
            v-if="member.user_id !== currentUserId"
            type="button"
            class="flex-shrink-0 rounded p-1 text-n-slate-9 hover:bg-n-ruby-3 hover:text-n-ruby-11"
            @click="removeMember(member.id)"
          >
            <Icon icon="i-lucide-x" class="size-3.5" />
          </button>
        </div>
      </div>
    </div>
  </Dialog>
</template>
