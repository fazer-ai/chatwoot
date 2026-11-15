<script setup>
// ninja-keys ships its footer as fixed English markup; filling its footer slot
// is the only way to translate it. The --ninja-* colors reach this light-DOM
// content because CSS custom properties inherit through the slot.
const HINTS = [
  { keys: ['i-lucide-corner-down-left'], label: 'SELECT' },
  { keys: ['i-lucide-arrow-down', 'i-lucide-arrow-up'], label: 'NAVIGATE' },
  { keys: ['esc'], label: 'CLOSE' },
  { keys: ['i-lucide-delete'], label: 'PARENT' },
];
</script>

<template>
  <div
    slot="footer"
    class="flex flex-wrap gap-x-4 gap-y-1 px-4 py-2 text-xs bg-[var(--ninja-footer-background)] text-[color:var(--ninja-secondary-text-color)] border-t border-n-weak"
  >
    <span
      v-for="hint in HINTS"
      :key="hint.label"
      class="flex items-center gap-1"
    >
      <span
        v-for="key in hint.keys"
        :key="key"
        class="flex items-center justify-center h-4 min-w-4 px-0.5 rounded bg-[var(--ninja-secondary-background-color)]"
      >
        <span v-if="key === 'esc'" class="leading-none">{{ key }}</span>
        <span v-else class="size-3" :class="key" />
      </span>
      {{ $t(`COMMAND_BAR.FOOTER.${hint.label}`) }}
    </span>
  </div>
</template>
