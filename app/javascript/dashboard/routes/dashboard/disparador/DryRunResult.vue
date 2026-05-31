<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import {
  skipReasonRows,
  skipReasonLabelKey,
  hasKnownCost,
  formatCostCents,
} from './helper/disparadorHelper';

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const isRunning = ref(false);
const summary = ref(null);
const disparoName = ref('');

const skipRows = computed(() => skipReasonRows(summary.value?.by_skip_reason));

const skipReasonText = reason => {
  const key = skipReasonLabelKey(reason);
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  return key ? t(key) : reason;
};

const costText = computed(() => {
  if (!summary.value) return '';
  if (hasKnownCost(summary.value.estimated_cost_cents)) {
    return formatCostCents(summary.value.estimated_cost_cents);
  }
  return t('DISPARADOR_MGMT.DRY_RUN.SUMMARY.COST_UNKNOWN');
});

const resolveError = message => {
  if (message === 'invalid_dry_run') {
    return t('DISPARADOR_MGMT.DRY_RUN.API.ERRORS.INVALID_DRY_RUN');
  }
  return message || t('DISPARADOR_MGMT.DRY_RUN.API.ERROR_MESSAGE');
};

const run = async disparo => {
  disparoName.value = disparo.name;
  summary.value = null;
  isRunning.value = true;
  dialogRef.value?.open();
  try {
    summary.value = await store.dispatch('disparador/dryRun', disparo.id);
  } catch (error) {
    useAlert(resolveError(error?.message));
    dialogRef.value?.close();
  } finally {
    isRunning.value = false;
  }
};

defineExpose({ run });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('DISPARADOR_MGMT.DRY_RUN.TITLE')"
    :description="t('DISPARADOR_MGMT.DRY_RUN.DESC', { name: disparoName })"
    :show-confirm-button="false"
    :cancel-button-label="t('DISPARADOR_MGMT.DRY_RUN.CLOSE')"
    width="lg"
    overflow-y-auto
  >
    <div
      v-if="isRunning"
      class="flex flex-col items-center justify-center gap-3 py-12"
    >
      <Spinner class="text-n-brand" :size="28" />
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t('DISPARADOR_MGMT.DRY_RUN.RUNNING') }}
      </p>
    </div>

    <div v-else-if="summary" class="flex flex-col gap-5">
      <div class="grid grid-cols-2 gap-3">
        <div
          class="flex flex-col gap-1 p-4 rounded-lg bg-n-alpha-1 outline outline-1 outline-n-weak"
        >
          <span class="text-3xl font-medium text-n-teal-11">
            {{ summary.total_eligible }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{ t('DISPARADOR_MGMT.DRY_RUN.SUMMARY.TOTAL_ELIGIBLE') }}
          </span>
        </div>
        <div
          class="flex flex-col gap-1 p-4 rounded-lg bg-n-alpha-1 outline outline-1 outline-n-weak"
        >
          <span class="text-3xl font-medium text-n-slate-12">
            {{ summary.total_skipped }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{ t('DISPARADOR_MGMT.DRY_RUN.SUMMARY.TOTAL_SKIPPED') }}
          </span>
        </div>
      </div>

      <div class="flex flex-col gap-2">
        <span class="text-heading-3 text-n-slate-12">
          {{ t('DISPARADOR_MGMT.DRY_RUN.SUMMARY.SKIP_BREAKDOWN') }}
        </span>
        <p v-if="!skipRows.length" class="mb-0 text-sm text-n-slate-11">
          {{ t('DISPARADOR_MGMT.DRY_RUN.SUMMARY.NO_SKIPS') }}
        </p>
        <ul v-else class="flex flex-col gap-px m-0 list-none">
          <li
            v-for="row in skipRows"
            :key="row.reason"
            class="flex items-center justify-between px-3 py-2 rounded-md odd:bg-n-alpha-1"
          >
            <span class="text-sm text-n-slate-12">
              {{ skipReasonText(row.reason) }}
            </span>
            <span class="text-sm font-medium tabular-nums text-n-slate-11">
              {{ row.count }}
            </span>
          </li>
        </ul>
      </div>

      <div
        class="flex items-center justify-between p-4 rounded-lg bg-n-alpha-1 outline outline-1 outline-n-weak"
      >
        <div class="flex flex-col gap-0.5">
          <span class="text-sm text-n-slate-11">
            {{ t('DISPARADOR_MGMT.DRY_RUN.SUMMARY.COST') }}
          </span>
          <span v-if="summary.cost_source" class="text-xs text-n-slate-10">
            {{
              t('DISPARADOR_MGMT.DRY_RUN.SUMMARY.COST_SOURCE', {
                source: summary.cost_source,
              })
            }}
          </span>
        </div>
        <span
          class="text-sm font-medium"
          :class="
            hasKnownCost(summary.estimated_cost_cents)
              ? 'text-n-slate-12'
              : 'text-n-amber-11'
          "
        >
          {{ costText }}
        </span>
      </div>
    </div>
  </Dialog>
</template>
