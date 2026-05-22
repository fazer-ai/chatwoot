<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const { t } = useI18n();

const isOpen = ref(false);

const accountId = useMapGetter('getCurrentAccountId');
const accountGetter = useMapGetter('accounts/getAccount');
const inboxGetter = useMapGetter('inboxes/getInbox');

const account = computed(() => accountGetter.value(accountId.value));
const simulatorInbox = computed(() =>
  inboxGetter.value(account.value?.simulator_inbox_id)
);
const websiteToken = computed(() => simulatorInbox.value?.website_token || '');

// `?_=<timestamp>` is a cache-buster: the user expects the modal to start
// fresh every time they open it from the sidebar, so the iframe never
// resumes a half-finished previous test session.
const iframeSrc = computed(() => {
  if (!websiteToken.value) return '';
  return `/simulator?website_token=${encodeURIComponent(websiteToken.value)}&_=${Date.now()}`;
});

const open = () => {
  isOpen.value = true;
};
const close = () => {
  isOpen.value = false;
};

const onBackdropClick = event => {
  if (event.target === event.currentTarget) close();
};
const onKeydown = event => {
  if (event.key === 'Escape') close();
};

onMounted(() => {
  emitter.on(BUS_EVENTS.OPEN_SIMULATOR, open);
  window.addEventListener('keydown', onKeydown);
});

onUnmounted(() => {
  emitter.off(BUS_EVENTS.OPEN_SIMULATOR, open);
  window.removeEventListener('keydown', onKeydown);
});
</script>

<template>
  <Teleport to="body">
    <div
      v-if="isOpen"
      class="fixed inset-0 z-[9999] flex items-center justify-center bg-black/40"
      role="dialog"
      aria-modal="true"
      @mousedown="onBackdropClick"
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
          v-if="iframeSrc"
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
