<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useInternalChatPro } from 'dashboard/composables/useInternalChatPro';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  feature: {
    type: String,
    default: 'polls',
    validator: v => ['polls', 'private_channels', 'search'].includes(v),
  },
  inline: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const { isSuperAdmin, isAdmin } = useInternalChatPro();

const dialogRef = ref(null);
const upgradeUrl = 'https://fazer.ai/kanban';

const descriptionKey = computed(() => {
  const map = {
    polls: 'INTERNAL_CHAT.PRO.POLLS_DESCRIPTION',
    private_channels: 'INTERNAL_CHAT.PRO.PRIVATE_CHANNELS_DESCRIPTION',
    search: 'INTERNAL_CHAT.PRO.SEARCH_DESCRIPTION',
  };
  return map[props.feature];
});

const descriptionParams = computed(() => {
  const map = {
    private_channels: { limit: 2 },
    search: { days: 90 },
  };
  return map[props.feature] || {};
});

function open() {
  dialogRef.value?.open();
}

defineExpose({ open });
</script>

<template>
  <!-- Inline mode: render card directly -->
  <div
    v-if="inline"
    class="flex flex-col rounded-xl border border-n-weak bg-n-solid-1 px-4 py-4 shadow"
  >
    <div class="mb-3 flex items-center gap-2">
      <span
        class="flex size-6 items-center justify-center rounded-full bg-n-solid-blue"
      >
        <Icon
          class="flex-shrink-0 text-n-brand size-[14px]"
          icon="i-lucide-lock-keyhole"
        />
      </span>
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('INTERNAL_CHAT.PRO.TITLE') }}
      </span>
    </div>
    <template v-if="isSuperAdmin">
      <p class="mb-3 text-sm text-n-slate-11">
        {{ t(descriptionKey, descriptionParams) }}
      </p>
      <a
        :href="upgradeUrl"
        target="_blank"
        rel="noopener noreferrer"
        class="flex w-full items-center justify-center rounded-xl bg-n-brand px-3 py-1.5 text-sm font-medium text-white hover:opacity-90"
      >
        {{ t('INTERNAL_CHAT.PRO.UPGRADE_NOW') }}
      </a>
    </template>
    <template v-else-if="isAdmin">
      <p class="text-sm text-n-slate-11">
        {{ t('INTERNAL_CHAT.PRO.ADMIN_MESSAGE') }}
      </p>
    </template>
    <template v-else>
      <p class="text-sm text-n-slate-11">
        {{ t('INTERNAL_CHAT.PRO.AGENT_MESSAGE') }}
      </p>
    </template>
  </div>

  <!-- Modal mode: render inside Dialog -->
  <Dialog
    v-else
    ref="dialogRef"
    :title="t('INTERNAL_CHAT.PRO.TITLE')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    width="sm"
  >
    <div class="flex flex-col">
      <div class="mb-4 flex items-center gap-2">
        <span
          class="flex size-6 items-center justify-center rounded-full bg-n-solid-blue"
        >
          <Icon
            class="flex-shrink-0 text-n-brand size-[14px]"
            icon="i-lucide-lock-keyhole"
          />
        </span>
        <span class="text-base font-medium text-n-slate-12">
          {{ t('INTERNAL_CHAT.PRO.TITLE') }}
        </span>
      </div>
      <template v-if="isSuperAdmin">
        <p class="mb-4 text-sm text-n-slate-11">
          {{ t(descriptionKey, descriptionParams) }}
        </p>
        <a
          :href="upgradeUrl"
          target="_blank"
          rel="noopener noreferrer"
          class="flex w-full items-center justify-center rounded-xl bg-n-brand px-4 py-2 text-sm font-medium text-white hover:opacity-90"
        >
          {{ t('INTERNAL_CHAT.PRO.UPGRADE_NOW') }}
        </a>
      </template>
      <template v-else-if="isAdmin">
        <p class="text-sm text-n-slate-11">
          {{ t('INTERNAL_CHAT.PRO.ADMIN_MESSAGE') }}
        </p>
      </template>
      <template v-else>
        <p class="text-sm text-n-slate-11">
          {{ t('INTERNAL_CHAT.PRO.AGENT_MESSAGE') }}
        </p>
      </template>
    </div>
  </Dialog>
</template>
