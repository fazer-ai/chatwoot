<script setup>
import { computed, onBeforeUnmount, watch, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
});

const store = useStore();
const { t } = useI18n();

// `history_import` is written by Whatsapp::IncomingMessageBaileysService on
// each `importMode: true` webhook batch the Baileys node service pushes back.
// Until the node service starts publishing those events, the snapshot stays
// nil and the whole section just hides itself.
const historyImport = computed(
  () => props.inbox?.provider_connection?.history_import
);

const status = computed(() => historyImport.value?.status);
const total = computed(() => historyImport.value?.total_batches);
const processed = computed(() => historyImport.value?.processed_batches || 0);
const messages = computed(() => historyImport.value?.messages_imported || 0);

const percent = computed(() => {
  if (!total.value || total.value <= 0) return null;
  const ratio = (processed.value / total.value) * 100;
  return Math.min(100, Math.max(0, Math.round(ratio)));
});

const formatDate = iso => {
  if (!iso) return null;
  try {
    return new Date(iso).toLocaleString();
  } catch {
    return iso;
  }
};

const startedAt = computed(() => formatDate(historyImport.value?.started_at));
const finishedAt = computed(() => formatDate(historyImport.value?.finished_at));

// Poll the inbox list while an import is running so the progress bar advances
// without the user having to refresh the page. Five seconds is rough enough
// that the network noise stays low; batches arrive in seconds anyway.
const POLL_INTERVAL_MS = 5000;
const pollHandle = ref(null);

const stopPolling = () => {
  if (pollHandle.value) {
    clearInterval(pollHandle.value);
    pollHandle.value = null;
  }
};

const startPolling = () => {
  if (pollHandle.value) return;
  pollHandle.value = setInterval(() => {
    store.dispatch('inboxes/get');
  }, POLL_INTERVAL_MS);
};

watch(
  status,
  newStatus => {
    if (newStatus === 'in_progress') {
      startPolling();
    } else {
      stopPolling();
    }
  },
  { immediate: true }
);

onBeforeUnmount(stopPolling);
</script>

<template>
  <div
    v-if="historyImport"
    class="flex flex-col gap-3 p-4 rounded-xl bg-n-solid-2 outline outline-1 outline-n-container"
  >
    <div class="flex items-center justify-between gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('INBOX_MGMT.SETTINGS_POPUP.BAILEYS_HISTORY_IMPORT.TITLE') }}
      </span>
      <span
        class="text-xs px-2 py-0.5 rounded-md"
        :class="
          status === 'completed'
            ? 'bg-n-teal-3 text-n-teal-11'
            : 'bg-n-blue-3 text-n-blue-11'
        "
      >
        {{
          status === 'completed'
            ? t(
                'INBOX_MGMT.SETTINGS_POPUP.BAILEYS_HISTORY_IMPORT.STATUS_COMPLETED'
              )
            : t(
                'INBOX_MGMT.SETTINGS_POPUP.BAILEYS_HISTORY_IMPORT.STATUS_IN_PROGRESS'
              )
        }}
      </span>
    </div>

    <div
      v-if="percent !== null"
      class="w-full h-2 rounded-full bg-n-alpha-2 overflow-hidden"
    >
      <div
        class="h-full bg-n-blue-9 transition-all duration-300"
        :style="{ width: `${percent}%` }"
      />
    </div>

    <div class="flex flex-wrap gap-x-6 gap-y-1 text-xs text-n-slate-11">
      <span v-if="total">
        {{
          t('INBOX_MGMT.SETTINGS_POPUP.BAILEYS_HISTORY_IMPORT.BATCHES', {
            processed,
            total,
          })
        }}
      </span>
      <span>
        {{
          t('INBOX_MGMT.SETTINGS_POPUP.BAILEYS_HISTORY_IMPORT.MESSAGES', {
            count: messages.toLocaleString(),
          })
        }}
      </span>
      <span v-if="startedAt">
        {{
          t('INBOX_MGMT.SETTINGS_POPUP.BAILEYS_HISTORY_IMPORT.STARTED_AT', {
            time: startedAt,
          })
        }}
      </span>
      <span v-if="finishedAt">
        {{
          t('INBOX_MGMT.SETTINGS_POPUP.BAILEYS_HISTORY_IMPORT.FINISHED_AT', {
            time: finishedAt,
          })
        }}
      </span>
    </div>
  </div>
  <!-- vue/no-root-v-if needs a sibling: this is intentional, the widget is hidden until the Baileys node pushes the first batch. -->
  <span v-else class="hidden" />
</template>
