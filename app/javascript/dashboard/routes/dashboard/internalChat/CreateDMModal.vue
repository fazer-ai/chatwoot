<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useRouter, useRoute } from 'vue-router';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const store = useStore();
const { t } = useI18n();
const router = useRouter();
const route = useRoute();

const dialogRef = ref(null);
const searchQuery = ref('');
const selectedAgentId = ref(null);
const isCreating = ref(false);

const currentUserId = computed(() => store.getters.getCurrentUser?.id);

const agents = computed(() => {
  return store.getters['agents/getAgents'] || [];
});

const filteredAgents = computed(() => {
  if (!searchQuery.value) return agents.value;
  const query = searchQuery.value.toLowerCase();
  return agents.value.filter(agent =>
    (agent.name || '').toLowerCase().includes(query)
  );
});

const isFormValid = computed(() => selectedAgentId.value !== null);

function open() {
  searchQuery.value = '';
  selectedAgentId.value = null;
  store.dispatch('agents/get');
  dialogRef.value?.open();
}

function selectAgent(agentId) {
  selectedAgentId.value = agentId;
}

async function handleConfirm() {
  if (!isFormValid.value) return;

  isCreating.value = true;
  try {
    const result = await store.dispatch('internalChat/create', {
      channel: { channel_type: 'dm' },
      member_ids: [selectedAgentId.value],
    });
    dialogRef.value?.close();
    router.push({
      name: 'internal_chat_dm',
      params: { accountId: route.params.accountId, channelId: result.id },
    });
  } catch {
    // error is handled by throwErrorMessage in the action
  } finally {
    isCreating.value = false;
  }
}

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('INTERNAL_CHAT.DM.NEW')"
    :confirm-button-label="t('INTERNAL_CHAT.DM.NEW')"
    :disable-confirm-button="!isFormValid"
    :is-loading="isCreating"
    @confirm="handleConfirm"
  >
    <div class="flex flex-col gap-3">
      <input
        v-model="searchQuery"
        type="text"
        class="w-full rounded-lg border border-n-slate-6 bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 placeholder-n-slate-10 outline-none focus:border-n-brand"
        :placeholder="t('INTERNAL_CHAT.DM.SELECT_AGENTS')"
      />
      <div class="flex flex-col gap-1 max-h-64 overflow-y-auto">
        <button
          v-for="agent in filteredAgents"
          :key="agent.id"
          type="button"
          class="flex items-center gap-3 rounded-lg px-3 py-2 text-sm text-left transition-colors"
          :class="
            selectedAgentId === agent.id
              ? 'bg-n-brand/10 text-n-slate-12'
              : 'text-n-slate-11 hover:bg-n-alpha-1'
          "
          @click="selectAgent(agent.id)"
        >
          <Avatar
            :name="agent.name || ''"
            :src="agent.thumbnail || ''"
            :size="28"
            rounded-full
          />
          <span class="flex-1 truncate">
            {{ agent.name }}
            <span v-if="agent.id === currentUserId" class="text-n-slate-10">
              {{ t('INTERNAL_CHAT.CHANNEL.YOU') }}
            </span>
          </span>
        </button>
        <p
          v-if="filteredAgents.length === 0"
          class="px-3 py-4 text-center text-sm text-n-slate-10"
        >
          {{ t('INTERNAL_CHAT.DM.SELECT_AGENTS') }}
        </p>
      </div>
    </div>
  </Dialog>
</template>
