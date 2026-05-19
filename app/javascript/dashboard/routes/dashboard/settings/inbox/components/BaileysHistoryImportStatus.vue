<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

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
const messages = computed(() => historyImport.value?.messages_imported || 0);

// Parse helpers — Baileys batches land with ISO timestamps generated on the
// Rails side, so timezones are already resolved before they reach us.
const parseIso = iso => {
  if (!iso) return null;
  const date = new Date(iso);
  return Number.isNaN(date.getTime()) ? null : date;
};

const formattedTime = computed(() => {
  const iso =
    historyImport.value?.finished_at || historyImport.value?.last_batch_at;
  const date = parseIso(iso);
  return date ? date.toLocaleTimeString() : null;
});

// Re-render every second so the relative time stays fresh without polling
// the backend. Polling is throttled to every 5s separately.
const now = ref(Date.now());
let tickHandle = null;

const lastBatchSecondsAgo = computed(() => {
  const date = parseIso(historyImport.value?.last_batch_at);
  if (!date) return null;
  return Math.max(0, Math.floor((now.value - date.getTime()) / 1000));
});

const relativeUpdated = computed(() => {
  const secs = lastBatchSecondsAgo.value;
  if (secs === null) return null;
  if (secs < 60) {
    return t(
      'INBOX_MGMT.SETTINGS_POPUP.BAILEYS_HISTORY_IMPORT.UPDATED_SECS_AGO',
      { secs }
    );
  }
  const mins = Math.floor(secs / 60);
  return t(
    'INBOX_MGMT.SETTINGS_POPUP.BAILEYS_HISTORY_IMPORT.UPDATED_MINS_AGO',
    {
      mins,
    }
  );
});

// Backend marks completed via a watchdog Sidekiq job after ~45s of no new
// batches. Polling stays light (5s) and stops as soon as we see the flip.
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

onMounted(() => {
  tickHandle = setInterval(() => {
    now.value = Date.now();
  }, 1000);
});

onBeforeUnmount(() => {
  stopPolling();
  if (tickHandle) clearInterval(tickHandle);
});
</script>

<template>
  <div
    v-if="historyImport"
    class="flex flex-col gap-2 p-4 rounded-xl bg-n-solid-2 outline outline-1 outline-n-container"
  >
    <div class="flex items-center justify-between gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('INBOX_MGMT.SETTINGS_POPUP.BAILEYS_HISTORY_IMPORT.TITLE') }}
      </span>
      <span
        class="text-xs px-2 py-0.5 rounded-md inline-flex items-center gap-1.5"
        :class="
          status === 'completed'
            ? 'bg-n-teal-3 text-n-teal-11'
            : 'bg-n-blue-3 text-n-blue-11'
        "
      >
        <Spinner v-if="status !== 'completed'" :size="10" />
        <i v-else class="i-lucide-check w-3 h-3" />
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

    <p class="text-sm text-n-slate-12 m-0">
      {{
        t('INBOX_MGMT.SETTINGS_POPUP.BAILEYS_HISTORY_IMPORT.MESSAGES', {
          count: messages.toLocaleString(),
        })
      }}
    </p>

    <p
      v-if="status === 'completed' && formattedTime"
      class="text-xs text-n-slate-11 m-0"
    >
      {{
        t('INBOX_MGMT.SETTINGS_POPUP.BAILEYS_HISTORY_IMPORT.FINISHED_AT', {
          time: formattedTime,
        })
      }}
    </p>
    <p v-else-if="relativeUpdated" class="text-xs text-n-slate-11 m-0">
      {{ relativeUpdated }}
    </p>
  </div>
  <!-- vue/no-root-v-if needs a sibling: this is intentional, the widget is hidden until the Baileys node pushes the first batch. -->
  <span v-else class="hidden" />
</template>
