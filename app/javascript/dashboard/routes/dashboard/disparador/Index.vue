<script setup>
import { computed, onBeforeMount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CampaignLayout from 'dashboard/components-next/Campaigns/CampaignLayout.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import CreateDisparo from './CreateDisparo.vue';
import DryRunResult from './DryRunResult.vue';
import TargetsView from './TargetsView.vue';
import { statusLabelKey } from './helper/disparadorHelper';

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();

const createDialog = ref(null);
const dryRunDialog = ref(null);
const targetsDialog = ref(null);
// The store action re-throws on a failed list load, so without this flag the
// failure would fall through to the empty state — indistinguishable from a
// genuinely empty account. We surface an in-view error + retry instead.
const loadError = ref(false);
// Tracks which row's shadow-run is in flight so only that button shows the
// loading state (the store flag is global to the module).
const runningShadowId = ref(null);

// The list is fetched from the paginated, read-only index on mount and persists
// across reloads. New drafts are appended locally by the create flow.
const records = computed(() => getters['disparador/getDisparos'].value);
const uiFlags = computed(() => getters['disparador/getUIFlags'].value);

const inboxesById = computed(() => {
  const map = {};
  getters['inboxes/getInboxes'].value.forEach(inbox => {
    map[inbox.id] = inbox;
  });
  return map;
});

const inboxNameFor = disparo => {
  const ids = disparo.inbox_ids || [];
  if (!ids.length) return '—';
  const first = inboxesById.value[ids[0]];
  if (!first) return '—';
  if (ids.length === 1) return first.name;
  return t('DISPARADOR_MGMT.LIST.INBOX_COUNT', ids.length, {
    named: { count: ids.length },
  });
};

const statusText = status => {
  const key = statusLabelKey(status);
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  return key ? t(key) : status;
};

const tableHeaders = computed(() => [
  t('DISPARADOR_MGMT.LIST.TABLE_HEADER.NAME'),
  t('DISPARADOR_MGMT.LIST.TABLE_HEADER.INBOX'),
  t('DISPARADOR_MGMT.LIST.TABLE_HEADER.STATUS'),
  t('DISPARADOR_MGMT.LIST.TABLE_HEADER.ACTION'),
]);

const settingsRoute = computed(() => ({
  name: 'disparador_settings',
  params: { accountId: store.getters.getCurrentAccountId },
}));

const openCreate = () => createDialog.value?.open();
const openDryRun = disparo => dryRunDialog.value?.run(disparo);
const openTargets = disparo => targetsDialog.value?.open(disparo);

// GAP B: shadow-run is only enabled once a disparo has an approved dry-run
// snapshot. The store holds the latest snapshot id per disparo; this reads it.
const snapshotIdFor = computed(
  () => disparo => getters['disparador/getSnapshotId'].value(disparo.id)
);

const resolveShadowRunError = message => {
  // A 422 here means the snapshot is missing/expired/config-changed; the store
  // already dropped it, so the operator must run a fresh dry-run before retrying.
  if (message === 'invalid_shadow_run') {
    return t('DISPARADOR_MGMT.SHADOW_RUN.API.ERRORS.INVALID_SHADOW_RUN');
  }
  return message || t('DISPARADOR_MGMT.SHADOW_RUN.API.ERROR_MESSAGE');
};

// Shadow-run persists the target set, then we surface the headline counts and
// open the targets view so the QA flow chains run -> inspect. It sends the
// snapshot id captured by the approved dry-run; without one it is a no-op (the
// button is disabled), and a 422 surfaces the re-dry-run prompt.
const runShadow = async disparo => {
  const snapshotId = snapshotIdFor.value(disparo);
  if (!snapshotId) {
    useAlert(t('DISPARADOR_MGMT.SHADOW_RUN.API.ERRORS.NEEDS_DRY_RUN'));
    return;
  }
  runningShadowId.value = disparo.id;
  try {
    const summary = await store.dispatch('disparador/shadowRun', {
      id: disparo.id,
      snapshotId,
    });
    useAlert(
      t('DISPARADOR_MGMT.SHADOW_RUN.API.SUCCESS_MESSAGE', {
        created: summary.created,
        eligible: summary.eligible,
        skipped: summary.skipped,
      })
    );
    openTargets(disparo);
  } catch (error) {
    useAlert(resolveShadowRunError(error?.message));
  } finally {
    runningShadowId.value = null;
  }
};

// The list load is the only fetch that gates the main view, so it is the only
// one we guard. A failure sets loadError so the template renders an in-view
// error + retry instead of the empty state. Retry re-dispatches the same get.
const fetchDisparos = async () => {
  loadError.value = false;
  try {
    await store.dispatch('disparador/get');
  } catch (error) {
    loadError.value = true;
  }
};

onBeforeMount(() => {
  fetchDisparos();
  store.dispatch('inboxes/get');
  store.dispatch('labels/get');
});
</script>

<template>
  <CampaignLayout
    :header-title="t('DISPARADOR_MGMT.HEADER')"
    :button-label="t('DISPARADOR_MGMT.HEADER_BTN_TXT')"
    @click="openCreate"
  >
    <template #action>
      <router-link
        :to="settingsRoute"
        class="absolute ltr:right-full rtl:left-full top-1/2 -translate-y-1/2 ltr:mr-2 rtl:ml-2"
      >
        <Button
          variant="faded"
          color="slate"
          size="sm"
          icon="i-lucide-sliders-horizontal"
          :label="t('DISPARADOR_MGMT.SETTINGS.HEADER_BTN_TXT')"
        />
      </router-link>
    </template>

    <div
      v-if="uiFlags.isFetching"
      class="flex items-center justify-center py-10 text-n-slate-11"
    >
      <Spinner />
    </div>

    <div
      v-else-if="loadError"
      class="flex flex-col items-center justify-center gap-3 py-12 text-center"
    >
      <p class="mb-0 text-heading-3 text-n-slate-12">
        {{ t('DISPARADOR_MGMT.LIST.LOAD_ERROR.TITLE') }}
      </p>
      <p class="max-w-md mb-0 text-sm text-n-slate-11">
        {{ t('DISPARADOR_MGMT.LIST.LOAD_ERROR.SUBTITLE') }}
      </p>
      <Button
        variant="faded"
        color="slate"
        size="sm"
        icon="i-lucide-refresh-cw"
        :label="t('DISPARADOR_MGMT.LIST.LOAD_ERROR.RETRY')"
        @click="fetchDisparos"
      />
    </div>

    <EmptyStateLayout
      v-else-if="!records.length"
      :title="t('DISPARADOR_MGMT.EMPTY_STATE.TITLE')"
      :subtitle="t('DISPARADOR_MGMT.EMPTY_STATE.SUBTITLE')"
      :action-perms="['administrator']"
      :show-backdrop="false"
    >
      <template #actions>
        <Button
          :label="t('DISPARADOR_MGMT.EMPTY_STATE.ACTION')"
          icon="i-lucide-plus"
          @click="openCreate"
        />
      </template>
    </EmptyStateLayout>

    <BaseTable v-else :headers="tableHeaders" :items="records">
      <template #row="{ items }">
        <BaseTableRow
          v-for="disparo in items"
          :key="disparo.id"
          :item="disparo"
        >
          <template #default>
            <BaseTableCell>
              <span class="text-body-main text-n-slate-12">
                {{ disparo.name }}
              </span>
            </BaseTableCell>

            <BaseTableCell>
              <span class="text-body-main text-n-slate-11">
                {{ inboxNameFor(disparo) }}
              </span>
            </BaseTableCell>

            <BaseTableCell>
              <span
                class="inline-flex items-center px-2 py-0.5 text-xs font-medium rounded-md text-n-slate-12 bg-n-alpha-2"
              >
                {{ statusText(disparo.status) }}
              </span>
            </BaseTableCell>

            <BaseTableCell align="end">
              <div class="flex justify-end flex-shrink-0 gap-2">
                <Button
                  variant="faded"
                  color="slate"
                  size="sm"
                  icon="i-lucide-play"
                  :label="t('DISPARADOR_MGMT.LIST.DRY_RUN')"
                  @click="openDryRun(disparo)"
                />
                <Button
                  v-tooltip="
                    snapshotIdFor(disparo)
                      ? undefined
                      : t('DISPARADOR_MGMT.LIST.SHADOW_RUN_DISABLED_HINT')
                  "
                  variant="faded"
                  color="slate"
                  size="sm"
                  icon="i-lucide-radio"
                  :label="t('DISPARADOR_MGMT.LIST.SHADOW_RUN')"
                  :disabled="!snapshotIdFor(disparo)"
                  :is-loading="
                    uiFlags.isShadowRunning && runningShadowId === disparo.id
                  "
                  @click="runShadow(disparo)"
                />
                <Button
                  variant="faded"
                  color="slate"
                  size="sm"
                  icon="i-lucide-users"
                  :label="t('DISPARADOR_MGMT.LIST.VIEW_TARGETS')"
                  @click="openTargets(disparo)"
                />
              </div>
            </BaseTableCell>
          </template>
        </BaseTableRow>
      </template>
    </BaseTable>

    <CreateDisparo ref="createDialog" />
    <DryRunResult ref="dryRunDialog" />
    <TargetsView ref="targetsDialog" />
  </CampaignLayout>
</template>
