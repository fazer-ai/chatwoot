<script setup>
import { ref, computed, onMounted } from 'vue';
import BaileysConnectionModal from '../../components/reports/BaileysConnectionModal.vue';

const props = defineProps({
  componentData: {
    type: Object,
    default: () => ({}),
  },
});

const inboxes = ref([]);
const counts = ref({ connected: 0, disconnected: 0 });
const loading = ref(false);
const error = ref(null);
const lastFetchedAt = ref(null);

const filters = ref({
  status: 'all',
  provider: 'all',
  phone: '',
  account_name: '',
  inbox_name: '',
  account_id: '',
});

const selectedInbox = ref(null);

// Provider labels and pill colors so the table reads at a glance.
const PROVIDER_LABELS = {
  baileys: 'Baileys',
  zapi: 'Z-API',
  whatsapp_cloud: 'WhatsApp Cloud',
  default: '360Dialog',
};

const providerLabel = provider => PROVIDER_LABELS[provider] || provider || '—';

const fetchData = async () => {
  loading.value = true;
  error.value = null;
  try {
    const res = await fetch(props.componentData.data_url, {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const body = await res.json();
    inboxes.value = body.inboxes || [];
    counts.value = body.counts || { connected: 0, disconnected: 0 };
    lastFetchedAt.value = new Date();
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
};

onMounted(fetchData);

const filteredInboxes = computed(() => {
  return inboxes.value.filter(row => {
    if (filters.value.status === 'connected' && !row.connected) return false;
    if (filters.value.status === 'disconnected' && row.connected) return false;
    if (
      filters.value.provider !== 'all' &&
      row.provider !== filters.value.provider
    )
      return false;
    if (
      filters.value.phone &&
      !String(row.phone_number || '')
        .toLowerCase()
        .includes(filters.value.phone.toLowerCase())
    )
      return false;
    if (
      filters.value.account_name &&
      !String(row.account_name || '')
        .toLowerCase()
        .includes(filters.value.account_name.toLowerCase())
    )
      return false;
    if (
      filters.value.inbox_name &&
      !String(row.inbox_name || '')
        .toLowerCase()
        .includes(filters.value.inbox_name.toLowerCase())
    )
      return false;
    if (
      filters.value.account_id &&
      String(row.account_id) !== String(filters.value.account_id).trim()
    )
      return false;
    return true;
  });
});

const accountNameOptions = computed(() => {
  const set = new Set(inboxes.value.map(i => i.account_name).filter(Boolean));
  return Array.from(set).sort();
});

const inboxNameOptions = computed(() => {
  const set = new Set(inboxes.value.map(i => i.inbox_name).filter(Boolean));
  return Array.from(set).sort();
});

// Providers actually present in the loaded data — keeps the dropdown
// from showing options that would always match zero rows.
const providerOptions = computed(() => {
  const set = new Set(inboxes.value.map(i => i.provider).filter(Boolean));
  return Array.from(set).sort();
});

const filteredCounts = computed(() =>
  filteredInboxes.value.reduce(
    (acc, row) => ({
      connected: acc.connected + (row.connected ? 1 : 0),
      disconnected: acc.disconnected + (row.connected ? 0 : 1),
    }),
    { connected: 0, disconnected: 0 }
  )
);

const filteredTotal = computed(
  () => filteredCounts.value.connected + filteredCounts.value.disconnected
);

const pct = n => {
  if (filteredTotal.value === 0) return '0%';
  return `${Math.round((n / filteredTotal.value) * 100)}%`;
};

const failureRate = row => {
  const total = row.outgoing_24h_total || 0;
  const failed = row.outgoing_24h_failed || 0;
  if (total === 0) return null;
  return (failed / total) * 100;
};

const failureRateLabel = row => {
  const rate = failureRate(row);
  if (rate === null) return '—';
  return `${rate.toFixed(1)}%`;
};

// Color tiers chosen so anything ≥ 5% pops red — that's where the operator
// should actively investigate. Below 1% (or zero traffic) is the baseline.
const failureRateClass = row => {
  const rate = failureRate(row);
  if (rate === null) return 'bg-n-alpha-2 text-n-slate-11';
  if (rate >= 5) return 'bg-n-ruby-3 text-n-ruby-12';
  if (rate >= 1) return 'bg-n-amber-3 text-n-amber-12';
  return 'bg-n-teal-3 text-n-teal-12';
};

const failureRateTooltip = row => {
  const total = row.outgoing_24h_total || 0;
  if (total === 0) return 'Sem mensagens enviadas nas últimas 24h';
  const failed = row.outgoing_24h_failed || 0;
  return `${failed} de ${total} mensagens enviadas nas últimas 24h ficaram sem confirmação do provider`;
};

const lastFetchedLabel = computed(() => {
  if (!lastFetchedAt.value) return '—';
  return lastFetchedAt.value.toLocaleTimeString('pt-BR');
});

const openConnectModal = inbox => {
  // The QR / reconnect modal only makes sense for socket-paired
  // providers (Baileys + Z-API). Cloud / 360Dialog inboxes are
  // always-on from our side, so don't even open the modal for them.
  if (!inbox.reconnect_supported) return;
  selectedInbox.value = inbox;
};

const closeConnectModal = () => {
  selectedInbox.value = null;
};

const onModalUpdated = async () => {
  await fetchData();
};

const resetFilters = () => {
  filters.value = {
    status: 'all',
    provider: 'all',
    phone: '',
    account_name: '',
    inbox_name: '',
    account_id: '',
  };
};
</script>

<template>
  <div class="overflow-auto bg-n-background w-full px-6">
    <div class="max-w-7xl mx-auto pb-12">
      <header class="flex flex-col gap-1 pt-6 pb-5">
        <div class="flex items-center justify-between gap-4 flex-wrap">
          <div>
            <h1 class="text-heading-1 text-n-slate-12">Inbox status</h1>
            <p class="text-sm text-n-slate-11 mt-1">
              Última atualização: {{ lastFetchedLabel }}
            </p>
          </div>
          <div class="flex gap-2">
            <button
              type="button"
              class="px-3 py-1.5 rounded-lg text-sm font-medium text-n-slate-12 bg-n-alpha-2 hover:bg-n-alpha-3 disabled:opacity-50"
              :disabled="loading"
              @click="resetFilters"
            >
              Limpar filtros
            </button>
            <button
              type="button"
              class="px-3 py-1.5 rounded-lg text-sm font-medium text-white bg-n-brand hover:bg-n-brand/90 disabled:opacity-50"
              :disabled="loading"
              @click="fetchData"
            >
              {{ loading ? 'Atualizando…' : 'Atualizar' }}
            </button>
          </div>
        </div>
      </header>

      <div
        v-if="error"
        class="px-4 py-3 mb-4 rounded-lg bg-n-ruby-3 text-n-ruby-12 text-sm"
      >
        Falha ao carregar dados: {{ error }}
      </div>

      <!-- KPI cards -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        <div
          class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-6 py-5"
        >
          <div class="text-sm text-n-slate-11">Total</div>
          <div class="text-3xl font-medium text-n-slate-12 mt-2">
            {{ filteredTotal }}
          </div>
        </div>
        <div
          class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-6 py-5"
        >
          <div class="text-sm text-n-slate-11">Conectado</div>
          <div class="flex items-baseline gap-2 mt-2">
            <span class="text-3xl font-medium text-n-teal-11">
              {{ filteredCounts.connected }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{ pct(filteredCounts.connected) }}
            </span>
          </div>
        </div>
        <div
          class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-6 py-5"
        >
          <div class="text-sm text-n-slate-11">Desconectado</div>
          <div class="flex items-baseline gap-2 mt-2">
            <span class="text-3xl font-medium text-n-ruby-11">
              {{ filteredCounts.disconnected }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{ pct(filteredCounts.disconnected) }}
            </span>
          </div>
        </div>
      </div>

      <!-- Filters -->
      <div
        class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-6 py-5 mb-6"
      >
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-6 gap-3">
          <label class="flex flex-col text-xs text-n-slate-11">
            Status
            <select
              v-model="filters.status"
              class="mt-1 bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-2 py-1.5 text-sm text-n-slate-12 focus:outline-n-brand"
            >
              <option value="all">Todos</option>
              <option value="connected">Conectado</option>
              <option value="disconnected">Desconectado</option>
            </select>
          </label>
          <label class="flex flex-col text-xs text-n-slate-11">
            Provider
            <select
              v-model="filters.provider"
              class="mt-1 bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-2 py-1.5 text-sm text-n-slate-12 focus:outline-n-brand"
            >
              <option value="all">Todos</option>
              <option
                v-for="provider in providerOptions"
                :key="provider"
                :value="provider"
              >
                {{ providerLabel(provider) }}
              </option>
            </select>
          </label>
          <label class="flex flex-col text-xs text-n-slate-11">
            Telefone
            <input
              v-model="filters.phone"
              type="text"
              class="mt-1 bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-2 py-1.5 text-sm text-n-slate-12 focus:outline-n-brand"
              placeholder="Ex: 5585…"
            />
          </label>
          <label class="flex flex-col text-xs text-n-slate-11">
            Account ID
            <input
              v-model="filters.account_id"
              type="text"
              class="mt-1 bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-2 py-1.5 text-sm text-n-slate-12 focus:outline-n-brand"
              placeholder="Ex: 42"
            />
          </label>
          <label class="flex flex-col text-xs text-n-slate-11">
            Account
            <input
              v-model="filters.account_name"
              list="superadmin-account-name-options"
              type="text"
              class="mt-1 bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-2 py-1.5 text-sm text-n-slate-12 focus:outline-n-brand"
              placeholder="Nome da account"
            />
            <datalist id="superadmin-account-name-options">
              <option
                v-for="opt in accountNameOptions"
                :key="opt"
                :value="opt"
              />
            </datalist>
          </label>
          <label class="flex flex-col text-xs text-n-slate-11">
            Inbox
            <input
              v-model="filters.inbox_name"
              list="superadmin-inbox-name-options"
              type="text"
              class="mt-1 bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-2 py-1.5 text-sm text-n-slate-12 focus:outline-n-brand"
              placeholder="Nome da caixa"
            />
            <datalist id="superadmin-inbox-name-options">
              <option v-for="opt in inboxNameOptions" :key="opt" :value="opt" />
            </datalist>
          </label>
        </div>
      </div>

      <!-- Inbox table — same look as /reports/overview Agent Table -->
      <div
        class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-6 py-5 mb-6"
      >
        <table class="w-full text-sm">
          <thead class="bg-n-slate-1 text-n-slate-12">
            <tr>
              <th class="text-left px-5 py-3 font-medium text-sm">Account</th>
              <th class="text-left px-5 py-3 font-medium text-sm">
                Account ID
              </th>
              <th class="text-left px-5 py-3 font-medium text-sm">Inbox</th>
              <th class="text-left px-5 py-3 font-medium text-sm">Provider</th>
              <th class="text-left px-5 py-3 font-medium text-sm">Telefone</th>
              <th class="text-left px-5 py-3 font-medium text-sm">Status</th>
              <th class="text-left px-5 py-3 font-medium text-sm">
                Não confirmadas 24h
              </th>
              <th
                class="text-left px-5 py-3 font-medium text-sm w-px whitespace-nowrap"
              >
                Ação
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-n-slate-2">
            <tr
              v-for="row in filteredInboxes"
              :key="row.inbox_id"
              class="text-n-slate-12 hover:bg-n-alpha-1"
            >
              <td class="px-5 py-4">{{ row.account_name }}</td>
              <td class="px-5 py-4 text-n-slate-11">{{ row.account_id }}</td>
              <td class="px-5 py-4">{{ row.inbox_name }}</td>
              <td class="px-5 py-4 text-n-slate-11">
                {{ providerLabel(row.provider) }}
              </td>
              <td class="px-5 py-4 font-mono text-xs">
                {{ row.phone_number }}
              </td>
              <td class="px-5 py-4">
                <span
                  v-if="row.connected"
                  class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-xs bg-n-teal-3 text-n-teal-12"
                >
                  <span class="w-1.5 h-1.5 rounded-full bg-n-teal-10" />
                  Conectado
                </span>
                <span
                  v-else
                  class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-xs bg-n-ruby-3 text-n-ruby-12"
                >
                  <span class="w-1.5 h-1.5 rounded-full bg-n-ruby-10" />
                  {{ row.connection || 'Desconectado' }}
                </span>
              </td>
              <td class="px-5 py-4">
                <span
                  class="inline-flex items-center px-2 py-0.5 rounded-full text-xs"
                  :class="failureRateClass(row)"
                  :title="failureRateTooltip(row)"
                >
                  {{ failureRateLabel(row) }}
                </span>
              </td>
              <td class="px-5 py-4 w-px whitespace-nowrap">
                <!-- Only the socket-paired providers expose a
                     reconnect-via-QR flow; cloud / 360Dialog don't. -->
                <template v-if="row.reconnect_supported">
                  <button
                    v-if="!row.connected"
                    type="button"
                    class="px-2.5 py-1 rounded-lg bg-n-brand text-white text-xs font-medium hover:bg-n-brand/90"
                    @click="openConnectModal(row)"
                  >
                    Conectar dispositivo
                  </button>
                  <button
                    v-else
                    type="button"
                    class="px-2.5 py-1 rounded-lg bg-n-alpha-2 text-n-slate-12 text-xs font-medium hover:bg-n-alpha-3"
                    @click="openConnectModal(row)"
                  >
                    Detalhes
                  </button>
                </template>
                <span v-else class="text-xs text-n-slate-10">—</span>
              </td>
            </tr>
            <tr v-if="!filteredInboxes.length">
              <td colspan="8" class="px-5 py-8 text-center text-n-slate-11">
                Nenhuma inbox encontrada com os filtros atuais.
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <BaileysConnectionModal
      v-if="selectedInbox"
      :inbox="selectedInbox"
      @close="closeConnectModal"
      @updated="onModalUpdated"
    />
  </div>
</template>
