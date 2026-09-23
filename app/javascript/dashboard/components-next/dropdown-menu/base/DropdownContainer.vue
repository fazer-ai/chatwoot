<script setup>
import { ref } from 'vue';
import { onKeyStroke, useToggle } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import DropdownFloating from './DropdownFloating.vue';
import { provideDropdownContext, useDropdownTeleport } from './provider.js';

const emit = defineEmits(['close']);
const [isOpen, toggle] = useToggle(false);

const teleport = useDropdownTeleport();
const containerRef = ref(null);

// A getter, not a computed: consumers swap the trigger element as their state changes — a multi
// select trades its placeholder for a chips button once something is picked.
const getTrigger = () => containerRef.value?.firstElementChild ?? null;

const closeMenu = () => {
  if (isOpen.value) {
    emit('close');
    toggle(false);
  }
};

// Escape closes an open menu, and only the menu: the event is marked handled so a panel or dialog
// around it stays open. Listening on the document runs this before a panel's window listener.
onKeyStroke(
  'Escape',
  event => {
    if (!isOpen.value) return;
    event.preventDefault();
    closeMenu();
  },
  { target: document }
);

// A teleported menu sits outside the container, so clicks inside it read as clicks outside.
const clickOutsideHandler = [closeMenu, { ignore: ['[data-dropdown-menu]'] }];

provideDropdownContext({
  isOpen,
  toggle,
  closeMenu,
});
</script>

<template>
  <div
    ref="containerRef"
    v-on-click-outside="clickOutsideHandler"
    class="relative space-y-2"
  >
    <slot name="trigger" :is-open :toggle="() => toggle()" />
    <template v-if="isOpen">
      <DropdownFloating v-if="teleport" :trigger="getTrigger">
        <slot />
      </DropdownFloating>
      <div v-else class="absolute">
        <slot />
      </div>
    </template>
  </div>
</template>
