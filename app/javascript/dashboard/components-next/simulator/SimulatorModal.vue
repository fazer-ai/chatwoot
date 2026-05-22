<script setup>
import { computed, onMounted, onUnmounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { useMapGetter } from 'dashboard/composables/store';
import { useSimulatorState } from 'dashboard/composables/useSimulatorState';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const { t } = useI18n();
const route = useRoute();

const { hasOpened, isVisible, openSimulator, minimiseSimulator } =
  useSimulatorState();

const accountId = useMapGetter('getCurrentAccountId');
const accountGetter = useMapGetter('accounts/getAccount');
const inboxGetter = useMapGetter('inboxes/getInbox');
const currentChat = useMapGetter('getSelectedChat');

const account = computed(() => accountGetter.value(accountId.value));
const simulatorInbox = computed(() =>
  inboxGetter.value(account.value?.simulator_inbox_id)
);
const simulatorInboxId = computed(() => simulatorInbox.value?.id);

const websiteToken = computed(() => simulatorInbox.value?.website_token || '');
const iframeSrc = computed(() => {
  if (!websiteToken.value) return '';
  return `/simulator?website_token=${encodeURIComponent(websiteToken.value)}`;
});

// The launcher becomes a *contextual* entry point: it only appears
// when the operator is actually viewing the Simulador inbox in the
// dashboard. Two routes match:
//   1) the inbox conversation list  -> `route.params.inbox_id` set.
//   2) a specific conversation that belongs to the simulator inbox
//      -> route may not have :inbox_id, so fall back to the
//      currently-selected chat's `inbox_id`.
const isOnSimulatorInbox = computed(() => {
  if (!simulatorInboxId.value) return false;
  const routeInboxId = Number(route.params.inbox_id);
  if (routeInboxId && routeInboxId === simulatorInboxId.value) return true;
  const chatInboxId = currentChat.value?.inbox_id;
  return !!chatInboxId && chatInboxId === simulatorInboxId.value;
});

// When the operator navigates away from the simulator inbox while
// the panel is open, auto-minimise so the panel doesn't keep
// floating over an unrelated dashboard surface.
watch(isOnSimulatorInbox, value => {
  if (!value && isVisible.value) {
    minimiseSimulator();
  }
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
      <button
        type="button"
        class="absolute top-2 right-2 z-10 w-8 h-8 flex items-center justify-center rounded-full bg-black/30 hover:bg-black/50 text-white"
        :aria-label="t('SIMULATOR.MODAL.MINIMISE')"
        @click="minimiseSimulator"
      >
        <i class="i-lucide-minus size-5" />
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
    <!--
      Floating launcher bubble. Visibility is contextual: it only
      appears when the operator is actually viewing the Simulador
      inbox in the dashboard, and only while the simulator panel is
      not already on screen. Clicking on a different inbox or any
      other dashboard surface hides the bubble automatically.
    -->
    <button
      v-show="isOnSimulatorInbox && !isVisible"
      type="button"
      class="simulator-launcher fixed bottom-4 right-4 z-[9998] w-14 h-14 flex items-center justify-center rounded-full bg-n-amber-3 text-n-amber-11 outline outline-1 outline-n-amber-5 hover:bg-n-amber-4 shadow-lg transition-colors"
      :title="t('SIMULATOR.LAUNCHER.OPEN')"
      :aria-label="t('SIMULATOR.LAUNCHER.OPEN')"
      @click="openSimulator"
    >
      <i class="i-lucide-message-circle size-7" />
    </button>
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

// Pulse the floating launcher the same way the sidebar pill pulses
// when minimised, so the two "click here to come back" affordances
// feel like one connected gesture.
@keyframes simulator-launcher-pulse {
  0%,
  100% {
    box-shadow: 0 0 0 0 rgba(245, 158, 11, 0.55);
  }
  50% {
    box-shadow: 0 0 0 8px rgba(245, 158, 11, 0);
  }
}

.simulator-launcher {
  animation: simulator-launcher-pulse 1.6s ease-in-out infinite;
}
</style>
