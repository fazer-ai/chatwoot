<script setup>
import { computed, ref, watch, onMounted, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// Modal that blocks the user when there is at least one pending
// Operations Notification. Shows ONE notification at a time; clicking
// "Entendi" acknowledges it (backend records ip + user_agent) and
// advances to the next pending one. When the queue is empty the modal
// closes and the rest of the app boot continues — including the
// Release Notes modal that watches a separate signal.
//
// Poll cadence: every 30s (POLL_INTERVAL_MS). This is the "MVP B"
// option from the original spec. PR 3 will switch this to ActionCable
// push for the `immediate` trigger.

const POLL_INTERVAL_MS = 30_000;

const store = useStore();
const { t } = useI18n();

const dialogRef = ref(null);
const pollHandle = ref(null);

const pending = computed(
  () => store.getters['operationsNotifications/getPending']
);
const uiFlags = computed(
  () => store.getters['operationsNotifications/getUIFlags']
);

// We always show the OLDEST-published pending notification first so the
// queue drains in arrival order. Backend already orders by severity DESC
// then created_at DESC, so flipping the array gives oldest-first.
const currentNotification = computed(() => {
  if (!pending.value.length) return null;
  return [...pending.value].reverse()[0];
});

const isEmergency = computed(
  () => currentNotification.value?.severity === 'emergency'
);

watch(currentNotification, next => {
  if (next) dialogRef.value?.open();
  else dialogRef.value?.close();
});

const acknowledgeCurrent = async () => {
  const id = currentNotification.value?.id;
  if (!id) return;
  await store.dispatch('operationsNotifications/acknowledge', id);
  // After acknowledge, the store removes the item from `pending`;
  // the `watch(currentNotification)` handler then either opens the
  // next one or closes the dialog.
};

const startPolling = () => {
  if (pollHandle.value) return;
  pollHandle.value = window.setInterval(() => {
    store.dispatch('operationsNotifications/fetchPending');
  }, POLL_INTERVAL_MS);
};

const stopPolling = () => {
  if (pollHandle.value) {
    window.clearInterval(pollHandle.value);
    pollHandle.value = null;
  }
};

onMounted(() => {
  store.dispatch('operationsNotifications/fetchPending');
  startPolling();
});

onBeforeUnmount(() => {
  stopPolling();
});
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="lg"
    position="center"
    :show-cancel-button="false"
    :show-confirm-button="false"
  >
    <div v-if="currentNotification" class="flex flex-col gap-4">
      <div
        v-if="isEmergency"
        class="px-3 py-2 text-sm font-medium border rounded-md bg-n-ruby-3 border-n-ruby-7 text-n-ruby-11"
      >
        {{ t('OPERATIONS_NOTIFICATIONS.EMERGENCY_BADGE') }}
      </div>
      <div
        v-else
        class="px-3 py-2 text-sm font-medium border rounded-md bg-n-blue-3 border-n-blue-7 text-n-blue-11"
      >
        {{ t('OPERATIONS_NOTIFICATIONS.INFO_BADGE') }}
      </div>
      <h3 class="text-base font-semibold text-n-slate-12">
        {{ currentNotification.title }}
      </h3>
      <p class="text-sm whitespace-pre-wrap text-n-slate-12">
        {{ currentNotification.body }}
      </p>
      <p v-if="pending.length > 1" class="text-xs text-n-slate-10">
        {{
          t('OPERATIONS_NOTIFICATIONS.MORE_PENDING', {
            count: pending.length - 1,
          })
        }}
      </p>
    </div>
    <template #footer>
      <div class="flex items-center justify-end w-full">
        <Button
          color="blue"
          :label="t('OPERATIONS_NOTIFICATIONS.ACKNOWLEDGE')"
          type="button"
          :is-loading="uiFlags.isAcknowledging"
          @click="acknowledgeCurrent"
        />
      </div>
    </template>
  </Dialog>
</template>
