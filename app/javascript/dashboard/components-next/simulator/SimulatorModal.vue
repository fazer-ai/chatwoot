<script setup>
import { computed, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { useMapGetter } from 'dashboard/composables/store';
import { useSimulatorState } from 'dashboard/composables/useSimulatorState';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const { t } = useI18n();

const {
  hasOpened,
  isVisible,
  openSimulator,
  minimiseSimulator,
  closeSimulator,
} = useSimulatorState();

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

// onClickOutside fires for any click whose target is outside the panel
// element. Iframe clicks are absorbed by the iframe document context
// and never bubble to the parent, so clicking inside the simulator UI
// won't trigger the minimise. Sidebar / dashboard / settings clicks
// will, which is the whole point: the operator can switch between the
// simulator and AurisChat without explicitly closing the modal.
const onClickOutside = () => {
  if (!isVisible.value) return;
  minimiseSimulator();
};

const handleOpenEvent = () => openSimulator();

onMounted(() => {
  emitter.on(BUS_EVENTS.OPEN_SIMULATOR, handleOpenEvent);
});

onUnmounted(() => {
  emitter.off(BUS_EVENTS.OPEN_SIMULATOR, handleOpenEvent);
});
</script>

<template>
  <Teleport to="body">
    <div
      v-show="hasOpened && isVisible"
      v-on-click-outside="onClickOutside"
      class="simulator-modal-frame fixed z-[9999] bg-white shadow-2xl rounded-xl overflow-hidden flex flex-col"
      role="dialog"
      aria-modal="false"
    >
      <div class="absolute top-2 right-2 z-10 flex items-center gap-1.5">
        <button
          type="button"
          class="w-8 h-8 flex items-center justify-center rounded-full bg-black/30 hover:bg-black/50 text-white"
          :aria-label="t('SIMULATOR.MODAL.MINIMISE')"
          @click="minimiseSimulator"
        >
          <i class="i-lucide-minus size-5" />
        </button>
        <button
          type="button"
          class="w-8 h-8 flex items-center justify-center rounded-full bg-black/30 hover:bg-black/50 text-white"
          :aria-label="t('SIMULATOR.MODAL.CLOSE')"
          @click="closeSimulator"
        >
          <i class="i-lucide-x size-5" />
        </button>
      </div>
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
  </Teleport>
</template>

<style lang="scss" scoped>
.simulator-modal-frame {
  // Anchored to the bottom-right so the operator can keep dashboard
  // surfaces visible while the simulator is open. 30vw x 80vh sizing
  // mirrors the original brief; the 360px floor keeps the iframe
  // legible on smaller displays. The fixed offsets give it a little
  // breathing room from the edges.
  bottom: 1rem;
  right: 1rem;
  width: 30vw;
  min-width: 360px;
  height: 80vh;
}
</style>
