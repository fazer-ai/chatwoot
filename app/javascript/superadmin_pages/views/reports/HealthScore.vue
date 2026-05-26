<script setup>
import { ref, computed, onMounted } from 'vue';

const props = defineProps({
  componentData: {
    type: Object,
    default: () => ({}),
  },
});

const accounts = ref([]);
const counts = ref({
  red: 0,
  yellow: 0,
  green: 0,
  green_strong: 0,
  unscored: 0,
});
const computedAt = ref(null);
const loading = ref(false);
const error = ref(null);
const lastFetchedAt = ref(null);

const filters = ref({
  band: 'all',
  account_name: '',
  account_id: '',
});

const sortBy = ref('score');
const sortDir = ref('asc');

// Tracks which row is expanded to show the metric breakdown.
const expandedAccountId = ref(null);

const METRIC_LABELS = {
  ai_active_rate: 'IA ativa rolling',
  handoff_rate: 'Taxa de handoff IA→humano',
  inbox_uptime: 'Uptime das inboxes WhatsApp',
  daily_agent_activity: 'Uso diário pelos agentes',
  manager_engagement: 'Engajamento do manager',
};

// Each metric belongs to one of the 3 score groups. The drill-down shows a
// colored chip per card so the operator can tell at a glance which group
// is dragging the score down.
const METRIC_GROUP = {
  ai_active_rate: 'outcomes',
  handoff_rate: 'outcomes',
  inbox_uptime: 'operational',
  daily_agent_activity: 'engagement',
  manager_engagement: 'engagement',
};

const GROUP_LABELS = {
  outcomes: 'Outcomes',
  operational: 'Operational',
  engagement: 'Engagement',
};

// Chip colors avoid the score band palette (red / amber / teal) AND keep
// the 3 groups visually distinct from each other: gray (neutral) for
// Outcomes, blue for Operational, iris (lavender) for Engagement.
const GROUP_CHIP_CLASSES = {
  outcomes: 'bg-n-gray-3 text-n-gray-12 border-n-gray-6',
  operational: 'bg-n-blue-3 text-n-blue-12 border-n-blue-6',
  engagement: 'bg-n-iris-3 text-n-iris-12 border-n-iris-6',
};

const MISSING_REASON_LABELS = {
  account_in_implementation_phase: 'Conta em fase de implementação (0–45 dias)',
  insufficient_volume: 'Volume de conversas insuficiente para avaliação',
  no_whatsapp_inboxes: 'Conta sem inbox WhatsApp',
  no_manager_role: 'Conta sem usuário com perfil manager',
};

const KILL_CLAUSE_LABELS = {
  all_whatsapp_inboxes_disconnected: 'Todas as inboxes WhatsApp desconectadas',
  no_agent_activity: 'Zero atividade de agente nos últimos 14 dias',
};

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
    accounts.value = body.accounts || [];
    counts.value = body.counts || counts.value;
    computedAt.value = body.computed_at || null;
    lastFetchedAt.value = new Date();
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
};

onMounted(fetchData);

const filteredAccounts = computed(() => {
  return accounts.value.filter(row => {
    if (
      filters.value.band !== 'all' &&
      (row.band || 'unscored') !== filters.value.band
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
      filters.value.account_id &&
      String(row.account_id) !== String(filters.value.account_id).trim()
    )
      return false;
    return true;
  });
});

const sortedAccounts = computed(() => {
  const rows = [...filteredAccounts.value];
  const dir = sortDir.value === 'asc' ? 1 : -1;

  return rows.sort((a, b) => {
    let aVal;
    let bVal;
    if (sortBy.value === 'account_name') {
      aVal = (a.account_name || '').toLowerCase();
      bVal = (b.account_name || '').toLowerCase();
    } else if (
      ['outcomes', 'operational', 'engagement'].includes(sortBy.value)
    ) {
      aVal = a.groups?.[sortBy.value]?.sub_score_normalized ?? -1;
      bVal = b.groups?.[sortBy.value]?.sub_score_normalized ?? -1;
    } else {
      aVal = a.score ?? -1;
      bVal = b.score ?? -1;
    }
    if (aVal < bVal) return -1 * dir;
    if (aVal > bVal) return 1 * dir;
    return 0;
  });
});

const toggleSort = column => {
  if (sortBy.value === column) {
    sortDir.value = sortDir.value === 'asc' ? 'desc' : 'asc';
  } else {
    sortBy.value = column;
    sortDir.value = column === 'account_name' ? 'asc' : 'asc';
  }
};

const toggleExpand = accountId => {
  expandedAccountId.value =
    expandedAccountId.value === accountId ? null : accountId;
};

const resetFilters = () => {
  filters.value = { band: 'all', account_name: '', account_id: '' };
};

const lastFetchedLabel = computed(() => {
  if (!lastFetchedAt.value) return '—';
  return lastFetchedAt.value.toLocaleTimeString('pt-BR');
});

const computedAtLabel = computed(() => {
  if (!computedAt.value) return '—';
  try {
    return new Date(computedAt.value).toLocaleDateString('pt-BR');
  } catch (e) {
    return computedAt.value;
  }
});

const totalAccounts = computed(() => accounts.value.length);

// Band → tailwind classes for the colored badges.
const bandClasses = band => {
  switch (band) {
    case 'red':
      return 'bg-n-ruby-3 text-n-ruby-12 border border-n-ruby-6';
    case 'yellow':
      return 'bg-n-amber-3 text-n-amber-12 border border-n-amber-6';
    case 'green':
      return 'bg-n-teal-3 text-n-teal-12 border border-n-teal-6';
    case 'green_strong':
      return 'bg-n-teal-4 text-n-teal-12 border border-n-teal-7 font-semibold';
    default:
      return 'bg-n-alpha-2 text-n-slate-11 border border-n-weak';
  }
};

// Returns a band label for a sub-score (per-group cell), reusing the same
// thresholds as the total score so the colors are consistent.
const bandForScore = score => {
  if (score === null || score === undefined) return null;
  if (score <= 40) return 'red';
  if (score <= 65) return 'yellow';
  if (score <= 85) return 'green';
  return 'green_strong';
};

const formatRawValue = (key, value) => {
  if (value === null || value === undefined) return '—';
  if (typeof value === 'number') {
    if (key.endsWith('_pct')) return `${(value * 100).toFixed(1)}%`;
    return String(value);
  }
  if (typeof value === 'boolean') return value ? 'sim' : 'não';
  if (Array.isArray(value)) {
    // `inboxes` arrives as [{ phone_number, connected }]: render each as
    // "phone (conectada|desconectada)" so the operator sees the offending
    // line, not the useless "[object Object]" toString.
    if (
      key === 'inboxes' &&
      value.every(item => item && typeof item === 'object')
    ) {
      return value
        .map(
          ({ phone_number: phone, connected }) =>
            `${phone || '—'} (${connected ? 'conectada' : 'desconectada'})`
        )
        .join(', ');
    }
    if (value.every(item => typeof item !== 'object' || item === null)) {
      return value.join(', ');
    }
    return value.map(item => JSON.stringify(item)).join(', ');
  }
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
};

const arrow = column => {
  if (sortBy.value !== column) return '';
  return sortDir.value === 'asc' ? '↑' : '↓';
};
</script>

<template>
  <div class="overflow-auto bg-n-background w-full px-6">
    <div class="max-w-7xl mx-auto pb-12">
      <header class="flex flex-col gap-1 pt-6 pb-5">
        <div class="flex items-center justify-between gap-4 flex-wrap">
          <div>
            <h1 class="text-heading-1 text-n-slate-12">Health Score</h1>
            <p class="text-sm text-n-slate-11 mt-1">
              Snapshot diário · gerado em {{ computedAtLabel }} · atualizado em
              {{ lastFetchedLabel }}
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
      <div class="grid grid-cols-2 md:grid-cols-5 gap-4 mb-6">
        <div
          class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-5 py-4"
        >
          <div class="text-sm text-n-slate-11">Total</div>
          <div class="text-3xl font-medium text-n-slate-12 mt-2">
            {{ totalAccounts }}
          </div>
        </div>
        <div
          class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-5 py-4"
        >
          <div class="text-sm text-n-ruby-11">🔴 Vermelho</div>
          <div class="text-3xl font-medium text-n-ruby-11 mt-2">
            {{ counts.red }}
          </div>
        </div>
        <div
          class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-5 py-4"
        >
          <div class="text-sm text-n-amber-11">🟡 Amarelo</div>
          <div class="text-3xl font-medium text-n-amber-11 mt-2">
            {{ counts.yellow }}
          </div>
        </div>
        <div
          class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-5 py-4"
        >
          <div class="text-sm text-n-teal-11">🟢 Verde</div>
          <div class="text-3xl font-medium text-n-teal-11 mt-2">
            {{ counts.green + counts.green_strong }}
          </div>
        </div>
        <div
          class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-5 py-4"
        >
          <div class="text-sm text-n-slate-11">Sem score</div>
          <div class="text-3xl font-medium text-n-slate-11 mt-2">
            {{ counts.unscored }}
          </div>
        </div>
      </div>

      <!-- Filters -->
      <div
        class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-6 py-5 mb-6"
      >
        <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
          <label class="flex flex-col text-xs text-n-slate-11">
            Banda
            <select
              v-model="filters.band"
              class="mt-1 bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-2 py-1.5 text-sm text-n-slate-12 focus:outline-n-brand"
            >
              <option value="all">Todas</option>
              <option value="red">🔴 Vermelho (≤40)</option>
              <option value="yellow">🟡 Amarelo (41–65)</option>
              <option value="green">🟢 Verde (66–85)</option>
              <option value="green_strong">🟢 Verde forte (86–100)</option>
              <option value="unscored">Sem score</option>
            </select>
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
              type="text"
              class="mt-1 bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-2 py-1.5 text-sm text-n-slate-12 focus:outline-n-brand"
              placeholder="Nome da account"
            />
          </label>
        </div>
      </div>

      <!-- Health score table -->
      <div
        class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-6 py-5 mb-6"
      >
        <table class="w-full text-sm">
          <thead class="bg-n-slate-1 text-n-slate-12">
            <tr>
              <th class="text-left px-5 py-3 font-medium text-sm w-8" />
              <th
                class="text-left px-5 py-3 font-medium text-sm cursor-pointer select-none"
                @click="toggleSort('account_name')"
              >
                Account {{ arrow('account_name') }}
              </th>
              <th class="text-left px-5 py-3 font-medium text-sm">ID</th>
              <th
                class="text-center px-5 py-3 font-medium text-sm cursor-pointer select-none"
                @click="toggleSort('score')"
              >
                Total {{ arrow('score') }}
              </th>
              <th
                class="text-center px-5 py-3 font-medium text-sm cursor-pointer select-none"
                @click="toggleSort('outcomes')"
              >
                Outcomes {{ arrow('outcomes') }}
              </th>
              <th
                class="text-center px-5 py-3 font-medium text-sm cursor-pointer select-none"
                @click="toggleSort('operational')"
              >
                Operational {{ arrow('operational') }}
              </th>
              <th
                class="text-center px-5 py-3 font-medium text-sm cursor-pointer select-none"
                @click="toggleSort('engagement')"
              >
                Engagement {{ arrow('engagement') }}
              </th>
              <th class="text-left px-5 py-3 font-medium text-sm">
                Atualizado
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-n-slate-2">
            <template v-for="row in sortedAccounts" :key="row.account_id">
              <tr
                class="text-n-slate-12 hover:bg-n-alpha-1 cursor-pointer"
                @click="toggleExpand(row.account_id)"
              >
                <td class="px-5 py-4 text-center">
                  <span
                    :class="
                      expandedAccountId === row.account_id
                        ? 'rotate-90 inline-block transition-transform'
                        : 'inline-block transition-transform'
                    "
                    >▶</span
                  >
                </td>
                <td class="px-5 py-4">{{ row.account_name }}</td>
                <td class="px-5 py-4 text-n-slate-11 font-mono text-xs">
                  {{ row.account_id }}
                </td>
                <td class="px-5 py-4 text-center">
                  <span
                    v-if="row.score !== null"
                    :class="`inline-flex items-center justify-center min-w-12 px-2 py-0.5 rounded-md text-sm font-medium ${bandClasses(row.band)}`"
                    :title="
                      row.kill_clause
                        ? `Cap por kill clause: ${KILL_CLAUSE_LABELS[row.kill_clause] || row.kill_clause}`
                        : ''
                    "
                  >
                    {{ row.score }}
                  </span>
                  <span v-else class="text-n-slate-10 text-sm">—</span>
                </td>
                <td class="px-5 py-4 text-center">
                  <span
                    v-if="
                      row.groups?.outcomes?.sub_score_normalized !==
                        undefined &&
                      row.groups.outcomes.sub_score_normalized !== null
                    "
                    :class="`inline-flex items-center justify-center min-w-12 px-2 py-0.5 rounded-md text-sm ${bandClasses(bandForScore(row.groups.outcomes.sub_score_normalized))}`"
                  >
                    {{ row.groups.outcomes.sub_score_normalized }}
                  </span>
                  <span
                    v-else
                    class="text-n-slate-10 text-sm"
                    title="Métrica indisponível"
                  >
                    —
                  </span>
                </td>
                <td class="px-5 py-4 text-center">
                  <span
                    v-if="
                      row.groups?.operational?.sub_score_normalized !==
                        undefined &&
                      row.groups.operational.sub_score_normalized !== null
                    "
                    :class="`inline-flex items-center justify-center min-w-12 px-2 py-0.5 rounded-md text-sm ${bandClasses(bandForScore(row.groups.operational.sub_score_normalized))}`"
                  >
                    {{ row.groups.operational.sub_score_normalized }}
                  </span>
                  <span
                    v-else
                    class="text-n-slate-10 text-sm"
                    title="Métrica indisponível"
                  >
                    —
                  </span>
                </td>
                <td class="px-5 py-4 text-center">
                  <span
                    v-if="
                      row.groups?.engagement?.sub_score_normalized !==
                        undefined &&
                      row.groups.engagement.sub_score_normalized !== null
                    "
                    :class="`inline-flex items-center justify-center min-w-12 px-2 py-0.5 rounded-md text-sm ${bandClasses(bandForScore(row.groups.engagement.sub_score_normalized))}`"
                  >
                    {{ row.groups.engagement.sub_score_normalized }}
                  </span>
                  <span
                    v-else
                    class="text-n-slate-10 text-sm"
                    title="Métrica indisponível"
                  >
                    —
                  </span>
                </td>
                <td class="px-5 py-4 text-n-slate-11 text-xs">
                  {{ row.captured_on || '—' }}
                </td>
              </tr>
              <!-- Expanded breakdown row -->
              <tr v-if="expandedAccountId === row.account_id">
                <td colspan="8" class="px-5 py-5 bg-n-alpha-black1">
                  <div v-if="!row.captured_on" class="text-sm text-n-slate-11">
                    Esta conta ainda não tem um snapshot calculado. O job diário
                    roda às 03:00 UTC; aguarde a próxima execução.
                  </div>
                  <template v-else>
                    <div
                      v-if="row.kill_clause"
                      class="mb-4 px-3 py-2 rounded-lg bg-n-ruby-3 text-n-ruby-12 text-sm"
                    >
                      ⚠️ Score limitado por
                      <strong>{{
                        KILL_CLAUSE_LABELS[row.kill_clause] || row.kill_clause
                      }}</strong>
                    </div>
                    <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                      <div
                        v-for="(metric, key) in row.metrics"
                        :key="key"
                        class="bg-n-solid-2 outline outline-1 outline-n-container rounded-lg px-4 py-3"
                      >
                        <div
                          class="flex items-baseline justify-between gap-2 mb-1"
                        >
                          <div class="flex items-center gap-2 min-w-0">
                            <span
                              :class="`inline-flex items-center px-1.5 py-0.5 rounded-md text-[10px] font-medium uppercase tracking-wide border ${GROUP_CHIP_CLASSES[METRIC_GROUP[key]] || ''}`"
                            >
                              {{ GROUP_LABELS[METRIC_GROUP[key]] || '—' }}
                            </span>
                            <span class="text-sm font-medium text-n-slate-12">
                              {{ METRIC_LABELS[key] || key }}
                            </span>
                          </div>
                          <span
                            v-if="!metric.missing"
                            :class="`inline-flex items-center justify-center min-w-10 px-2 py-0.5 rounded-md text-xs font-medium ${bandClasses(bandForScore(metric.sub_score))}`"
                          >
                            {{ metric.sub_score }}
                          </span>
                          <span v-else class="text-xs text-n-slate-10">
                            indisponível
                          </span>
                        </div>
                        <div class="text-xs text-n-slate-11">
                          Peso normal: {{ metric.weight_normal }}% · aplicado:
                          {{ metric.weight_applied }}%
                        </div>
                        <div
                          v-if="metric.missing && metric.reason"
                          class="mt-2 text-xs text-n-slate-11 italic"
                        >
                          {{
                            MISSING_REASON_LABELS[metric.reason] ||
                            metric.reason
                          }}
                        </div>
                        <div
                          v-if="
                            !metric.missing &&
                            metric.raw &&
                            Object.keys(metric.raw).length > 0
                          "
                          class="mt-2 grid grid-cols-2 gap-x-3 gap-y-0.5 text-xs text-n-slate-11"
                        >
                          <template
                            v-for="(value, rawKey) in metric.raw"
                            :key="rawKey"
                          >
                            <span class="text-n-slate-10">{{ rawKey }}:</span>
                            <span class="font-mono">{{
                              formatRawValue(rawKey, value)
                            }}</span>
                          </template>
                        </div>
                      </div>
                    </div>
                  </template>
                </td>
              </tr>
            </template>
            <tr v-if="!sortedAccounts.length">
              <td colspan="8" class="px-5 py-8 text-center text-n-slate-11">
                Nenhuma account encontrada com os filtros atuais.
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>
