<script setup>
defineProps({
  disableBranding: {
    type: Boolean,
    default: false,
  },
});
</script>

<template>
  <div
    v-if="!disableBranding"
    class="px-0 py-3 flex justify-center text-xs text-n-slate-11"
  >
    <!-- eslint-disable vue/no-bare-strings-in-template @intlify/vue-i18n/no-raw-text -->
    <span>powered by&nbsp;</span>
    <a
      href="https://auris.ia.br"
      target="_blank"
      rel="noopener noreferrer"
      class="text-n-slate-11 hover:text-n-brand no-underline"
    >
      auris.ia.br
    </a>
    <!-- eslint-enable vue/no-bare-strings-in-template @intlify/vue-i18n/no-raw-text -->
  </div>
</template>
