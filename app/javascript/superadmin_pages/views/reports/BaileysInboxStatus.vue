<script setup>
import { ref, computed, onMounted } from 'vue';
import PieChart from '../../components/reports/PieChart.vue';
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
  phone: '',
  account_name: '',
  inbox_name: '',
  account_id: '',
});

const selectedInbox = ref(null);

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

const chartCollection = computed(() => ({
  labels: ['Conectado', 'Desconectado'],
  datasets: [
    {
      data: [filteredCounts.value.connected, filteredCounts.value.disconnected],
      backgroundColor: ['#10b981', '#ef4444'],
      hoverBackgroundColor: ['#059669', '#dc2626'],
    },
  ],
}));

const lastFetchedLabel = computed(() => {
  if (!lastFetchedAt.value) return '—';
  return lastFetchedAt.value.toLocaleTimeString('pt-BR');
});

const openConnectModal = inbox => {
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
    phone: '',
    account_name: '',
    inbox_name: '',
    account_id: '',
  };
};
</script>

<template>
  <div class="w-full h-full">
    <header class="main-content__header" role="banner">
      <h1 id="page-title" class="main-content__page-title">
        Inbox status Baileys
      </h1>
    </header>

    <section class="main-content__body">
      <div class="flex items-center justify-between mb-4 gap-3 flex-wrap">
        <div class="text-sm text-slate-500">
          Última atualização:
          <span class="font-medium text-slate-700">{{ lastFetchedLabel }}</span>
        </div>
        <div class="flex gap-2">
          <button
            type="button"
            class="px-3 py-1.5 rounded bg-slate-100 hover:bg-slate-200 text-sm text-slate-700 disabled:opacity-50"
            :disabled="loading"
            @click="resetFilters"
          >
            Limpar filtros
          </button>
          <button
            type="button"
            class="px-3 py-1.5 rounded bg-blue-500 hover:bg-blue-600 text-sm text-white disabled:opacity-50"
            :disabled="loading"
            @click="fetchData"
          >
            {{ loading ? 'Atualizando…' : 'Atualizar' }}
          </button>
        </div>
      </div>

      <div v-if="error" class="text-sm text-red-600 mb-4">
        Falha ao carregar dados: {{ error }}
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-6">
        <div>
          <div class="bg-white border border-slate-200 rounded p-4 mb-4">
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
              <label class="flex flex-col text-xs text-slate-600">
                Status
                <select
                  v-model="filters.status"
                  class="mt-1 border border-slate-300 rounded px-2 py-1 text-sm"
                >
                  <option value="all">Todos</option>
                  <option value="connected">Conectado</option>
                  <option value="disconnected">Desconectado</option>
                </select>
              </label>
              <label class="flex flex-col text-xs text-slate-600">
                Telefone
                <input
                  v-model="filters.phone"
                  type="text"
                  class="mt-1 border border-slate-300 rounded px-2 py-1 text-sm"
                  placeholder="Ex: 5585…"
                />
              </label>
              <label class="flex flex-col text-xs text-slate-600">
                Account ID
                <input
                  v-model="filters.account_id"
                  type="text"
                  class="mt-1 border border-slate-300 rounded px-2 py-1 text-sm"
                  placeholder="Ex: 42"
                />
              </label>
              <label class="flex flex-col text-xs text-slate-600">
                Account
                <input
                  v-model="filters.account_name"
                  list="superadmin-account-name-options"
                  type="text"
                  class="mt-1 border border-slate-300 rounded px-2 py-1 text-sm"
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
              <label class="flex flex-col text-xs text-slate-600">
                Inbox
                <input
                  v-model="filters.inbox_name"
                  list="superadmin-inbox-name-options"
                  type="text"
                  class="mt-1 border border-slate-300 rounded px-2 py-1 text-sm"
                  placeholder="Nome da caixa"
                />
                <datalist id="superadmin-inbox-name-options">
                  <option
                    v-for="opt in inboxNameOptions"
                    :key="opt"
                    :value="opt"
                  />
                </datalist>
              </label>
            </div>
          </div>

          <div class="bg-white border border-slate-200 rounded overflow-hidden">
            <table class="w-full text-sm">
              <thead class="bg-slate-50 text-slate-600 text-xs uppercase">
                <tr>
                  <th class="text-left px-3 py-2">Account</th>
                  <th class="text-left px-3 py-2">Account ID</th>
                  <th class="text-left px-3 py-2">Inbox</th>
                  <th class="text-left px-3 py-2">Telefone</th>
                  <th class="text-left px-3 py-2">Status</th>
                  <th class="text-right px-3 py-2">Ação</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="row in filteredInboxes"
                  :key="row.inbox_id"
                  class="border-t border-slate-100"
                >
                  <td class="px-3 py-2">{{ row.account_name }}</td>
                  <td class="px-3 py-2 text-slate-500">{{ row.account_id }}</td>
                  <td class="px-3 py-2">{{ row.inbox_name }}</td>
                  <td class="px-3 py-2 font-mono text-xs">
                    {{ row.phone_number }}
                  </td>
                  <td class="px-3 py-2">
                    <span
                      v-if="row.connected"
                      class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs bg-emerald-50 text-emerald-700"
                    >
                      <span class="w-2 h-2 rounded-full bg-emerald-500" />
                      Conectado
                    </span>
                    <span
                      v-else
                      class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs bg-red-50 text-red-700"
                    >
                      <span class="w-2 h-2 rounded-full bg-red-500" />
                      {{ row.connection || 'Desconectado' }}
                    </span>
                  </td>
                  <td class="px-3 py-2 text-right">
                    <button
                      v-if="!row.connected"
                      type="button"
                      class="px-2 py-1 rounded bg-blue-500 text-white text-xs hover:bg-blue-600"
                      @click="openConnectModal(row)"
                    >
                      Conectar dispositivo
                    </button>
                    <button
                      v-else
                      type="button"
                      class="px-2 py-1 rounded bg-slate-100 text-slate-600 text-xs hover:bg-slate-200"
                      @click="openConnectModal(row)"
                    >
                      Detalhes
                    </button>
                  </td>
                </tr>
                <tr v-if="!filteredInboxes.length">
                  <td colspan="6" class="px-3 py-6 text-center text-slate-400">
                    Nenhuma inbox Baileys encontrada com os filtros atuais.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <aside class="bg-white border border-slate-200 rounded p-4">
          <h2 class="text-sm font-semibold text-slate-700 mb-3">
            Resumo (filtrado)
          </h2>
          <div class="flex flex-col gap-2 text-sm mb-4">
            <div class="flex justify-between">
              <span class="text-slate-600">Conectado</span>
              <span class="font-medium text-emerald-600">
                {{ filteredCounts.connected }} ({{
                  pct(filteredCounts.connected)
                }})
              </span>
            </div>
            <div class="flex justify-between">
              <span class="text-slate-600">Desconectado</span>
              <span class="font-medium text-red-600">
                {{ filteredCounts.disconnected }} ({{
                  pct(filteredCounts.disconnected)
                }})
              </span>
            </div>
            <div
              class="flex justify-between border-t border-slate-100 pt-2 mt-1"
            >
              <span class="text-slate-600">Total</span>
              <span class="font-medium">{{ filteredTotal }}</span>
            </div>
          </div>
          <div class="h-[260px]">
            <PieChart :collection="chartCollection" />
          </div>
        </aside>
      </div>
    </section>

    <BaileysConnectionModal
      v-if="selectedInbox"
      :inbox="selectedInbox"
      @close="closeConnectModal"
      @updated="onModalUpdated"
    />
  </div>
</template>
