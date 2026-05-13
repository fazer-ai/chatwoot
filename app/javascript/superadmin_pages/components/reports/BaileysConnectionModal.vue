<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';

const props = defineProps({
  inbox: { type: Object, required: true },
});
const emit = defineEmits(['close', 'updated']);

const state = ref({
  connection: props.inbox.connection || 'close',
  qr_data_url: null,
  error: null,
});
const loading = ref(false);
const showLabel = computed(() => {
  switch (state.value.connection) {
    case 'open':
      return 'Conectado';
    case 'connecting':
      return 'Aguardando QR Code';
    case 'reconnecting':
      return 'Reconectando…';
    default:
      return 'Desconectado';
  }
});

let pollHandle = null;
const POLL_INTERVAL_MS = 3000;

const csrfToken = () =>
  document.querySelector('meta[name="csrf-token"]')?.content || '';

const apiUrl = action => {
  const base = `/super_admin/inboxes/${props.inbox.inbox_id}/baileys_connection`;
  return action ? `${base}/${action}` : base;
};

const callBaileys = async (method, action) => {
  const url = apiUrl(action);
  const res = await fetch(url, {
    method,
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      'X-CSRF-Token': csrfToken(),
    },
    credentials: 'same-origin',
  });
  if (!res.ok) {
    let message = `HTTP ${res.status}`;
    try {
      const body = await res.json();
      if (body?.error) message = body.error;
    } catch (e) {
      // ignore
    }
    throw new Error(message);
  }
  return res.json();
};

const refresh = async () => {
  try {
    const next = await callBaileys('GET');
    state.value = next;
  } catch (e) {
    state.value = { ...state.value, error: e.message };
  }
};

const setup = async () => {
  loading.value = true;
  try {
    const next = await callBaileys('POST');
    state.value = next;
  } catch (e) {
    state.value = { ...state.value, error: e.message };
  } finally {
    loading.value = false;
  }
};

const disconnect = async () => {
  loading.value = true;
  try {
    const next = await callBaileys('DELETE');
    state.value = next;
  } catch (e) {
    state.value = { ...state.value, error: e.message };
  } finally {
    loading.value = false;
  }
};

const close = () => {
  emit('updated');
  emit('close');
};

const stopPolling = () => {
  if (pollHandle) {
    window.clearInterval(pollHandle);
    pollHandle = null;
  }
};
const startPolling = () => {
  stopPolling();
  pollHandle = window.setInterval(refresh, POLL_INTERVAL_MS);
};

onMounted(async () => {
  await refresh();
  if (!state.value.connection || state.value.connection === 'close') {
    await setup();
  }
  startPolling();
});

onUnmounted(stopPolling);

watch(
  () => state.value.connection,
  v => {
    if (v === 'open') {
      // No need to keep hammering once connected — refresh once and slow down.
      stopPolling();
    }
  }
);
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/60"
    @click.self="close"
  >
    <div
      class="bg-n-background rounded-xl shadow-xl outline outline-1 outline-n-container w-[400px] max-w-[90vw] p-6 flex flex-col gap-4"
    >
      <div class="flex items-start justify-between gap-3">
        <div>
          <h2 class="text-lg font-medium text-n-slate-12">
            Conectar dispositivo
          </h2>
          <p class="text-sm text-n-slate-11 mt-1">
            {{ inbox.account_name }} · {{ inbox.inbox_name }}
          </p>
          <p class="text-sm text-n-slate-11">{{ inbox.phone_number }}</p>
        </div>
        <button
          type="button"
          class="text-n-slate-10 hover:text-n-slate-12 text-xl leading-none"
          @click="close"
        >
          ×
        </button>
      </div>

      <div
        class="bg-n-alpha-2 rounded-lg px-3 py-2 text-xs uppercase font-medium text-n-slate-11"
      >
        Status: {{ showLabel }}
      </div>

      <div
        v-if="state.error"
        class="px-3 py-2 rounded-lg bg-n-ruby-3 text-n-ruby-12 text-sm"
      >
        {{ state.error }}
      </div>

      <div class="flex flex-col items-center justify-center min-h-[280px]">
        <template v-if="state.connection === 'open'">
          <p class="text-n-teal-12 font-medium mb-3">Dispositivo conectado.</p>
          <button
            type="button"
            class="px-4 py-2 rounded-lg bg-n-ruby-3 text-n-ruby-12 text-sm font-medium hover:bg-n-ruby-4 disabled:opacity-50"
            :disabled="loading"
            @click="disconnect"
          >
            Desconectar
          </button>
        </template>

        <template
          v-else-if="state.connection === 'connecting' && state.qr_data_url"
        >
          <img
            :src="state.qr_data_url"
            alt="QR Code"
            class="w-[276px] h-[276px] rounded-lg"
          />
          <p class="text-xs text-n-slate-11 mt-3">
            Escaneie o QR no WhatsApp do dispositivo.
          </p>
        </template>

        <template v-else-if="state.connection === 'connecting'">
          <div
            class="w-8 h-8 rounded-full border-2 border-n-weak border-t-n-slate-11 animate-spin"
          />
          <p class="text-sm text-n-slate-11 mt-3">Gerando QR Code…</p>
        </template>

        <template v-else-if="state.connection === 'reconnecting'">
          <div
            class="w-8 h-8 rounded-full border-2 border-n-weak border-t-n-slate-11 animate-spin"
          />
          <p class="text-sm text-n-slate-11 mt-3">Reconectando…</p>
        </template>

        <template v-else>
          <button
            type="button"
            class="px-4 py-2 rounded-lg bg-n-brand text-white text-sm font-medium hover:bg-n-brand/90 disabled:opacity-50"
            :disabled="loading"
            @click="setup"
          >
            {{ loading ? 'Iniciando…' : 'Gerar QR Code' }}
          </button>
        </template>
      </div>
    </div>
  </div>
</template>
