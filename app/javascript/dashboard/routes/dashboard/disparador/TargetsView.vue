<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import {
  targetStateLabelKey,
  skipReasonLabelKey,
} from './helper/disparadorHelper';

// The targets endpoint caps each page at 50 and returns a bare array (no total),
// so paging is Prev/Next driven by the page-size heuristic below.
const TARGETS_PER_PAGE = 50;

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const isLoading = ref(false);
const targets = ref([]);
const disparoId = ref(null);
const disparoName = ref('');
const page = ref(1);
// The store getTargets re-throws on a failed fetch. Without this flag an
// initial-open failure leaves `targets` empty and falls through to the
// "no targets yet" empty state — telling the operator the disparo was never
// run when the fetch actually failed. We surface an in-view error + retry
// instead, but ONLY when there are no rows to show (a failed Next-page fetch
// mid-pagination keeps the existing rows + a transient toast).
const loadError = ref(false);

const hasTargets = computed(() => targets.value.length > 0);
// Next is only meaningful when the last page came back full (exactly the cap);
// a non-full page is the last one. Prev is available on any page beyond 1.
const hasNextPage = computed(() => targets.value.length === TARGETS_PER_PAGE);
const hasPrevPage = computed(() => page.value > 1);
const hasPager = computed(() => hasPrevPage.value || hasNextPage.value);

// Page 1 with no rows means the disparo was never shadow-run; a later empty page
// means we paged past the end of an exactly-full final page. The copy must
// differ so the user is never told "no targets exist" while Prev can walk back.
const isFirstPageEmpty = computed(() => !hasTargets.value && page.value === 1);

const stateText = state => {
  const key = targetStateLabelKey(state);
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  return key ? t(key) : state;
};

const skipReasonText = reason => {
  if (!reason) return '—';
  const key = skipReasonLabelKey(reason);
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  return key ? t(key) : reason;
};

const phonePresentText = present =>
  present
    ? t('DISPARADOR_MGMT.TARGETS.PHONE_PRESENT.YES')
    : t('DISPARADOR_MGMT.TARGETS.PHONE_PRESENT.NO');

const tableHeaders = computed(() => [
  t('DISPARADOR_MGMT.TARGETS.TABLE_HEADER.CONVERSATION'),
  t('DISPARADOR_MGMT.TARGETS.TABLE_HEADER.CONTACT'),
  t('DISPARADOR_MGMT.TARGETS.TABLE_HEADER.STATE'),
  t('DISPARADOR_MGMT.TARGETS.TABLE_HEADER.SKIP_REASON'),
  t('DISPARADOR_MGMT.TARGETS.TABLE_HEADER.PHONE_PRESENT'),
]);

const fetchPage = async nextPage => {
  isLoading.value = true;
  loadError.value = false;
  try {
    targets.value = await store.dispatch('disparador/getTargets', {
      id: disparoId.value,
      page: nextPage,
    });
    page.value = nextPage;
  } catch (error) {
    // No rows on screen => the failure would masquerade as an empty audience,
    // so show the in-view error + retry. With rows already shown (mid-pagination
    // failure), keep them and fall back to a transient toast.
    if (!hasTargets.value) {
      loadError.value = true;
    } else {
      useAlert(
        error?.message || t('DISPARADOR_MGMT.TARGETS.API.ERROR_MESSAGE')
      );
    }
  } finally {
    isLoading.value = false;
  }
};

const goToNextPage = () => fetchPage(page.value + 1);
const goToPrevPage = () => fetchPage(page.value - 1);
// page.value only advances on a successful fetch, so it still points at the
// page that failed — retry re-fetches exactly that page and clears the error.
const retry = () => fetchPage(page.value);

const open = disparo => {
  disparoId.value = disparo.id;
  disparoName.value = disparo.name;
  targets.value = [];
  page.value = 1;
  dialogRef.value?.open();
  fetchPage(1);
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('DISPARADOR_MGMT.TARGETS.TITLE')"
    :description="t('DISPARADOR_MGMT.TARGETS.DESC', { name: disparoName })"
    :show-confirm-button="false"
    :cancel-button-label="t('DISPARADOR_MGMT.TARGETS.CLOSE')"
    width="2xl"
    overflow-y-auto
  >
    <div
      v-if="isLoading && !hasTargets && isFirstPageEmpty"
      class="flex flex-col items-center justify-center gap-3 py-12"
    >
      <Spinner class="text-n-brand" :size="28" />
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t('DISPARADOR_MGMT.TARGETS.LOADING') }}
      </p>
    </div>

    <div
      v-else-if="loadError"
      class="flex flex-col items-center justify-center gap-3 py-12 text-center"
    >
      <p class="mb-0 text-heading-3 text-n-slate-12">
        {{ t('DISPARADOR_MGMT.TARGETS.LOAD_ERROR.TITLE') }}
      </p>
      <p class="max-w-md mb-0 text-sm text-n-slate-11">
        {{ t('DISPARADOR_MGMT.TARGETS.LOAD_ERROR.SUBTITLE') }}
      </p>
      <Button
        variant="faded"
        color="slate"
        size="sm"
        icon="i-lucide-refresh-cw"
        :label="t('DISPARADOR_MGMT.TARGETS.LOAD_ERROR.RETRY')"
        @click="retry"
      />
    </div>

    <div v-else class="flex flex-col gap-4">
      <div
        v-if="!hasTargets"
        class="flex flex-col items-center justify-center gap-1 py-12 text-center"
      >
        <p class="mb-0 text-heading-3 text-n-slate-12">
          {{
            isFirstPageEmpty
              ? t('DISPARADOR_MGMT.TARGETS.EMPTY.TITLE')
              : t('DISPARADOR_MGMT.TARGETS.EMPTY.END_TITLE')
          }}
        </p>
        <p class="mb-0 text-sm text-n-slate-11">
          {{
            isFirstPageEmpty
              ? t('DISPARADOR_MGMT.TARGETS.EMPTY.SUBTITLE')
              : t('DISPARADOR_MGMT.TARGETS.EMPTY.END_SUBTITLE')
          }}
        </p>
      </div>

      <BaseTable v-else :headers="tableHeaders" :items="targets">
        <template #row="{ items }">
          <BaseTableRow v-for="target in items" :key="target.id" :item="target">
            <template #default>
              <BaseTableCell>
                <span class="text-body-main tabular-nums text-n-slate-11">
                  {{ target.conversation_id }}
                </span>
              </BaseTableCell>

              <BaseTableCell>
                <span class="text-body-main tabular-nums text-n-slate-11">
                  {{ target.contact_id }}
                </span>
              </BaseTableCell>

              <BaseTableCell>
                <span
                  class="inline-flex items-center px-2 py-0.5 text-xs font-medium rounded-md"
                  :class="
                    target.state === 'queued'
                      ? 'text-n-teal-11 bg-n-teal-3'
                      : 'text-n-slate-12 bg-n-alpha-2'
                  "
                >
                  {{ stateText(target.state) }}
                </span>
              </BaseTableCell>

              <BaseTableCell>
                <span class="text-body-main text-n-slate-11">
                  {{ skipReasonText(target.primary_skip_reason) }}
                </span>
              </BaseTableCell>

              <BaseTableCell>
                <span
                  class="inline-flex items-center gap-1 text-body-main"
                  :class="
                    target.phone_present ? 'text-n-teal-11' : 'text-n-slate-10'
                  "
                >
                  <span
                    v-if="target.phone_present"
                    class="i-lucide-check size-4"
                  />
                  {{ phonePresentText(target.phone_present) }}
                </span>
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>

      <div v-if="hasPager" class="flex items-center justify-between">
        <span class="text-sm text-n-slate-11">
          {{ t('DISPARADOR_MGMT.TARGETS.PAGE', { page }) }}
        </span>
        <div class="flex items-center gap-2">
          <Button
            variant="faded"
            color="slate"
            size="sm"
            icon="i-lucide-chevron-left"
            :label="t('DISPARADOR_MGMT.TARGETS.PREV')"
            :disabled="!hasPrevPage || isLoading"
            @click="goToPrevPage"
          />
          <Button
            variant="faded"
            color="slate"
            size="sm"
            trailing-icon
            icon="i-lucide-chevron-right"
            :label="t('DISPARADOR_MGMT.TARGETS.NEXT')"
            :disabled="!hasNextPage || isLoading"
            @click="goToNextPage"
          />
        </div>
      </div>
    </div>
  </Dialog>
</template>
