<script setup>
import { computed, ref, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// "Central de Notificação" page. Shows up to 10 most recent operations
// notifications. Click on one re-opens it in a read-only modal — does
// NOT re-acknowledge (idempotent on backend anyway, but no point).

const store = useStore();
const { t, locale } = useI18n();

const records = computed(
  () => store.getters['operationsNotifications/getRecords']
);
const uiFlags = computed(
  () => store.getters['operationsNotifications/getUIFlags']
);

const selectedNotification = ref(null);
const detailDialogRef = ref(null);

const localeKey = computed(() =>
  locale.value === 'pt_BR' ? 'pt-BR' : 'en-US'
);

const formatDate = unixTs => {
  if (!unixTs) return '';
  return new Date(unixTs * 1000).toLocaleString(localeKey.value, {
    year: 'numeric',
    month: 'short',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
};

const preview = body => {
  if (!body) return '';
  return body.length > 160 ? `${body.slice(0, 160)}…` : body;
};

const openDetail = notification => {
  selectedNotification.value = notification;
  detailDialogRef.value?.open();
};

onMounted(() => {
  store.dispatch('operationsNotifications/fetchList');
});
</script>

<template>
  <div class="flex-1 min-h-0 overflow-y-auto">
    <div class="max-w-3xl px-6 py-6 mx-auto">
      <h1 class="text-xl font-semibold text-n-slate-12 mb-1">
        {{ t('OPERATIONS_NOTIFICATIONS.PAGE_TITLE') }}
      </h1>
      <p class="text-sm text-n-slate-11 mb-6">
        {{ t('OPERATIONS_NOTIFICATIONS.PAGE_DESCRIPTION') }}
      </p>

      <div
        v-if="uiFlags.fetchingList && records.length === 0"
        class="flex justify-center py-12"
      >
        <Spinner />
      </div>

      <div
        v-else-if="records.length === 0"
        class="px-6 py-12 text-sm text-center text-n-slate-11 border border-n-weak rounded-lg"
      >
        {{ t('OPERATIONS_NOTIFICATIONS.EMPTY_STATE') }}
      </div>

      <ol v-else class="flex flex-col gap-3">
        <li
          v-for="record in records"
          :key="record.id"
          class="bg-n-surface-1 border border-n-weak rounded-lg p-4 cursor-pointer hover:border-n-strong"
          @click="openDetail(record)"
        >
          <header class="flex items-start justify-between gap-3 mb-1">
            <h2
              class="text-sm font-semibold text-n-slate-12 flex items-center gap-2"
            >
              <span
                v-if="record.severity === 'emergency'"
                class="text-n-ruby-11"
                aria-hidden="true"
              >
                {{ t('OPERATIONS_NOTIFICATIONS.EMERGENCY_ICON') }}
              </span>
              {{ record.title }}
            </h2>
            <span class="text-xs text-n-slate-11 flex-shrink-0">
              {{ formatDate(record.published_at) }}
            </span>
          </header>
          <p class="text-xs text-n-slate-11 whitespace-pre-wrap">
            {{ preview(record.body) }}
          </p>
          <p
            v-if="record.acknowledged_at"
            class="mt-2 text-[10px] text-n-slate-10"
          >
            {{
              t('OPERATIONS_NOTIFICATIONS.ACKED_AT', {
                icon: t('OPERATIONS_NOTIFICATIONS.ACK_ICON'),
                date: formatDate(record.acknowledged_at),
              })
            }}
          </p>
        </li>
      </ol>
    </div>

    <Dialog
      ref="detailDialogRef"
      type="edit"
      width="lg"
      position="center"
      :show-cancel-button="false"
      :show-confirm-button="false"
      :title="selectedNotification?.title || ''"
    >
      <div v-if="selectedNotification" class="flex flex-col gap-3">
        <div
          v-if="selectedNotification.severity === 'emergency'"
          class="px-3 py-2 text-sm font-medium border rounded-md bg-n-ruby-3 border-n-ruby-7 text-n-ruby-11"
        >
          {{ t('OPERATIONS_NOTIFICATIONS.EMERGENCY_BADGE') }}
        </div>
        <p class="text-xs text-n-slate-10">
          {{ formatDate(selectedNotification.published_at) }}
        </p>
        <p class="text-sm whitespace-pre-wrap text-n-slate-12">
          {{ selectedNotification.body }}
        </p>
      </div>
      <template #footer>
        <div class="flex items-center justify-end w-full">
          <Button
            variant="faded"
            color="slate"
            :label="t('OPERATIONS_NOTIFICATIONS.CLOSE')"
            type="button"
            @click="detailDialogRef?.close()"
          />
        </div>
      </template>
    </Dialog>
  </div>
</template>
