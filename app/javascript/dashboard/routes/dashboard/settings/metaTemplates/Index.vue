<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { picoSearch } from '@scmmishra/pico-search';

import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'shared/components/Spinner.vue';
import StatusBadge from './components/StatusBadge.vue';
import TemplateDetailDrawer from './components/TemplateDetailDrawer.vue';

import MetaTemplatesAPI from 'dashboard/api/metaTemplates';

const { t } = useI18n();
const store = useStore();

// Cloud WhatsApp inbox universe. Comes from the already-hydrated
// inboxes store — if a user reaches this page directly without inboxes
// loaded (deep link), we dispatch once on mount.
const inboxes = useMapGetter('inboxes/getInboxes');
const cloudInboxes = computed(() =>
  inboxes.value.filter(
    inbox =>
      inbox.channel_type === 'Channel::Whatsapp' &&
      inbox.provider === 'whatsapp_cloud'
  )
);

const selectedInboxId = ref(null);
const templates = ref([]);
const lastSyncedAt = ref(null);
const loading = ref(false);
const syncing = ref(false);
const search = ref('');
const statusFilter = ref('ALL');
const categoryFilter = ref('ALL');
const selectedTemplate = ref(null);
const drawerOpen = ref(false);

const STATUS_OPTIONS = [
  'ALL',
  'APPROVED',
  'PENDING',
  'REJECTED',
  'PAUSED',
  'DISABLED',
  'IN_APPEAL',
];
const CATEGORY_OPTIONS = ['ALL', 'MARKETING', 'UTILITY', 'AUTHENTICATION'];

// Client-side filter chain: status → category → free-text search on
// name. The API returns everything in one go so all filtering stays
// local — Meta template catalogs are small enough (dozens, not
// thousands) that this is fine.
const filteredTemplates = computed(() => {
  let list = templates.value;

  if (statusFilter.value !== 'ALL') {
    list = list.filter(
      t2 => (t2.status || '').toUpperCase() === statusFilter.value
    );
  }
  if (categoryFilter.value !== 'ALL') {
    list = list.filter(
      t2 => (t2.category || '').toUpperCase() === categoryFilter.value
    );
  }
  if (search.value.trim()) {
    list = picoSearch(list, search.value.trim(), ['name', 'language']);
  }
  return list;
});

const fetchTemplates = async () => {
  if (!selectedInboxId.value) return;
  loading.value = true;
  try {
    const { data } = await MetaTemplatesAPI.fetch({
      inboxId: selectedInboxId.value,
    });
    templates.value = data.templates || [];
    lastSyncedAt.value = data.last_synced_at;
  } catch (err) {
    useAlert(
      err?.response?.data?.error || t('META_TEMPLATES.ERRORS.FETCH_FAILED')
    );
    templates.value = [];
  } finally {
    loading.value = false;
  }
};

const runSync = async () => {
  if (!selectedInboxId.value || syncing.value) return;
  syncing.value = true;
  try {
    const { data } = await MetaTemplatesAPI.sync({
      inboxId: selectedInboxId.value,
    });
    templates.value = data.templates || [];
    lastSyncedAt.value = data.last_synced_at;
    useAlert(t('META_TEMPLATES.SYNC.SUCCESS'));
  } catch (err) {
    useAlert(err?.response?.data?.error || t('META_TEMPLATES.SYNC.FAILED'));
  } finally {
    syncing.value = false;
  }
};

const openDetail = template => {
  selectedTemplate.value = template;
  drawerOpen.value = true;
};

const closeDetail = () => {
  drawerOpen.value = false;
  selectedTemplate.value = null;
};

const formatDate = iso => {
  if (!iso) return '—';
  try {
    return new Date(iso).toLocaleString();
  } catch (_e) {
    return iso;
  }
};

// Auto-select the first Cloud inbox when the list resolves. If the user
// only has one, they never see the dropdown as a "picker" — it just
// stays there as a label. When cloudInboxes is empty (should not happen
// because the sidebar gate hides the menu, but handles the race where
// inboxes are still loading), the empty state below takes over.
watch(
  cloudInboxes,
  next => {
    if (!selectedInboxId.value && next.length > 0) {
      selectedInboxId.value = next[0].id;
    }
  },
  { immediate: true }
);

watch(selectedInboxId, () => {
  templates.value = [];
  lastSyncedAt.value = null;
  fetchTemplates();
});

onMounted(() => {
  if (!inboxes.value.length) {
    store.dispatch('inboxes/get');
  }
});
</script>

<template>
  <SettingsLayout
    :no-records-found="!loading && cloudInboxes.length === 0"
    :no-records-message="t('META_TEMPLATES.EMPTY.NO_CLOUD_INBOX')"
    :is-loading="loading && templates.length === 0"
    :loading-message="t('META_TEMPLATES.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('META_TEMPLATES.HEADER.TITLE')"
        :description="t('META_TEMPLATES.HEADER.DESCRIPTION')"
      />
    </template>

    <template #body>
      <div class="grid gap-4">
        <!-- Inbox selector + sync -->
        <div class="flex flex-wrap items-end gap-3 justify-between">
          <div class="flex flex-wrap items-end gap-3">
            <label class="flex flex-col gap-1 text-xs text-n-slate-11">
              {{ t('META_TEMPLATES.FILTERS.INBOX') }}
              <select
                v-model="selectedInboxId"
                class="min-w-64 border border-n-weak rounded-md px-3 py-1.5 text-sm bg-n-solid-1 text-n-slate-12"
              >
                <option
                  v-for="inbox in cloudInboxes"
                  :key="inbox.id"
                  :value="inbox.id"
                >
                  {{ inbox.name }}
                </option>
              </select>
            </label>
            <label class="flex flex-col gap-1 text-xs text-n-slate-11">
              {{ t('META_TEMPLATES.FILTERS.STATUS') }}
              <select
                v-model="statusFilter"
                class="min-w-40 border border-n-weak rounded-md px-3 py-1.5 text-sm bg-n-solid-1 text-n-slate-12"
              >
                <option v-for="s in STATUS_OPTIONS" :key="s" :value="s">
                  {{ t(`META_TEMPLATES.STATUS.${s}`, s) }}
                </option>
              </select>
            </label>
            <label class="flex flex-col gap-1 text-xs text-n-slate-11">
              {{ t('META_TEMPLATES.FILTERS.CATEGORY') }}
              <select
                v-model="categoryFilter"
                class="min-w-40 border border-n-weak rounded-md px-3 py-1.5 text-sm bg-n-solid-1 text-n-slate-12"
              >
                <option v-for="c in CATEGORY_OPTIONS" :key="c" :value="c">
                  {{ t(`META_TEMPLATES.CATEGORY.${c}`, c) }}
                </option>
              </select>
            </label>
            <div class="min-w-64">
              <Input
                v-model="search"
                :placeholder="t('META_TEMPLATES.FILTERS.SEARCH_PLACEHOLDER')"
              />
            </div>
          </div>
          <div class="flex items-center gap-2">
            <span v-if="lastSyncedAt" class="text-xs text-n-slate-11">
              {{ t('META_TEMPLATES.LAST_SYNCED') }}
              {{ formatDate(lastSyncedAt) }}
            </span>
            <Button
              sm
              faded
              slate
              :disabled="syncing || !selectedInboxId"
              @click="runSync"
            >
              <Spinner v-if="syncing" class="!w-4 !h-4 !p-0" />
              <span v-else>{{ t('META_TEMPLATES.SYNC.BUTTON') }}</span>
            </Button>
          </div>
        </div>

        <!-- Table -->
        <div
          v-if="!loading && filteredTemplates.length === 0"
          class="py-12 text-center text-n-slate-11"
        >
          {{
            templates.length === 0
              ? t('META_TEMPLATES.EMPTY.NO_TEMPLATES')
              : t('META_TEMPLATES.EMPTY.NO_MATCH')
          }}
        </div>

        <div v-else class="border border-n-weak rounded-lg overflow-hidden">
          <table class="w-full text-sm">
            <thead class="bg-n-alpha-1 text-n-slate-11 text-xs">
              <tr>
                <th class="text-left px-4 py-2 font-medium">
                  {{ t('META_TEMPLATES.TABLE.NAME') }}
                </th>
                <th class="text-left px-4 py-2 font-medium">
                  {{ t('META_TEMPLATES.TABLE.CATEGORY') }}
                </th>
                <th class="text-left px-4 py-2 font-medium">
                  {{ t('META_TEMPLATES.TABLE.LANGUAGE') }}
                </th>
                <th class="text-left px-4 py-2 font-medium">
                  {{ t('META_TEMPLATES.TABLE.STATUS') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="template in filteredTemplates"
                :key="`${template.id || template.name}-${template.language}`"
                class="hover:bg-n-alpha-1 cursor-pointer text-n-slate-12"
                @click="openDetail(template)"
              >
                <td class="px-4 py-3 font-medium">
                  {{ template.name }}
                </td>
                <td class="px-4 py-3 text-n-slate-11">
                  {{ template.category }}
                </td>
                <td class="px-4 py-3 text-n-slate-11">
                  {{ template.language }}
                </td>
                <td class="px-4 py-3">
                  <StatusBadge :status="template.status" />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <TemplateDetailDrawer
        :template="selectedTemplate"
        :open="drawerOpen"
        @close="closeDetail"
      />
    </template>
  </SettingsLayout>
</template>
