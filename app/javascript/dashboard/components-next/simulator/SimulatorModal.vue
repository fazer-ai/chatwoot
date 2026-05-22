<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const { t } = useI18n();

// `hasOpened` flips on the first sidebar click and stays true for the
// lifetime of the dashboard session. Together with `v-show` (not v-if)
// it means the iframe is created once and survives every close/reopen:
// the conversation the operator is testing in the simulator persists
// even if they minimise the modal, switch apps, navigate elsewhere in
// the dashboard, and click the sidebar pill again to come back.
const isOpen = ref(false);
const hasOpened = ref(false);

const accountId = useMapGetter('getCurrentAccountId');
const accountGetter = useMapGetter('accounts/getAccount');
const inboxGetter = useMapGetter('inboxes/getInbox');

const account = computed(() => accountGetter.value(accountId.value));
const simulatorInbox = computed(() =>
  inboxGetter.value(account.value?.simulator_inbox_id)
);
const websiteToken = computed(() => simulatorInbox.value?.website_token || '');

const iframeSrc = computed(() => {
  if (!websiteToken.value) return '';
  return `/simulator?website_token=${encodeURIComponent(websiteToken.value)}`;
});

const open = () => {
  isOpen.value = true;
  hasOpened.value = true;
};
const close = () => {
  isOpen.value = false;
};

onMounted(() => {
  emitter.on(BUS_EVENTS.OPEN_SIMULATOR, open);
});

onUnmounted(() => {
  emitter.off(BUS_EVENTS.OPEN_SIMULATOR, open);
});
</script>

<template>
  <Teleport to="body">
    <div
      v-show="hasOpened && isOpen"
      class="fixed inset-0 z-[9999] flex items-center justify-center bg-black/40 pointer-events-auto"
      role="dialog"
      aria-modal="true"
    >
      <div
        class="simulator-modal-frame relative rounded-xl bg-white shadow-2xl overflow-hidden flex flex-col"
      >
        <button
          type="button"
          class="absolute top-2 right-2 z-10 w-8 h-8 flex items-center justify-center rounded-full bg-black/30 hover:bg-black/50 text-white"
          :aria-label="t('SIMULATOR.MODAL.CLOSE')"
          @click="close"
        >
          <i class="i-lucide-x size-5" />
        </button>
        <iframe
          v-if="hasOpened && iframeSrc"
          :src="iframeSrc"
          :title="t('SIMULATOR.PLACEHOLDER.TITLE')"
          class="w-full h-full border-0"
          allow="clipboard-read; clipboard-write"
        />
        <div
          v-else
          class="flex flex-1 items-center justify-center p-6 text-center text-sm text-n-slate-11"
        >
          {{ t('SIMULATOR.LOADING') }}
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style lang="scss" scoped>
.simulator-modal-frame {
  // 30vw wide x 80vh tall mirrors the brief the team agreed on; the 360px
  // floor keeps the iframe legible on smaller laptop displays where 30%
  // collapses below the WhatsApp widget's minimum usable width.
  width: 30vw;
  min-width: 360px;
  height: 80vh;
}
</style>
