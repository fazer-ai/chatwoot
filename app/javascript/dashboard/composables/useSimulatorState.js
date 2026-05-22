import { ref } from 'vue';

// Module-level refs make these a singleton across the dashboard SPA, so
// the sidebar pill and the SimulatorModal share the same flag without
// going through Vuex. `hasOpened` is one-shot: it flips on the first
// open and stays true so the iframe stays mounted across minimise /
// restore. `isMinimised` is the live state the sidebar pulse reads.
const hasOpened = ref(false);
const isVisible = ref(false);
const isMinimised = ref(false);

const openSimulator = () => {
  hasOpened.value = true;
  isVisible.value = true;
  isMinimised.value = false;
};

const minimiseSimulator = () => {
  if (!hasOpened.value) return;
  isVisible.value = false;
  isMinimised.value = true;
};

const toggleSimulator = () => {
  if (!hasOpened.value || !isVisible.value) {
    openSimulator();
  } else {
    minimiseSimulator();
  }
};

const closeSimulator = () => {
  isVisible.value = false;
  isMinimised.value = false;
};

export function useSimulatorState() {
  return {
    hasOpened,
    isVisible,
    isMinimised,
    openSimulator,
    minimiseSimulator,
    toggleSimulator,
    closeSimulator,
  };
}
