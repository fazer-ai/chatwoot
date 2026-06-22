<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';

// Routes can opt into using the full available width (no max-w-5xl
// centred container) by declaring `meta: { fullWidth: true }`. Used by
// wide audit tables like the IA → Humano report so the grid fills the
// space freed up when the operator collapses the sidebar.
const route = useRoute();
const fullWidth = computed(() => Boolean(route.meta?.fullWidth));
</script>

<template>
  <div class="overflow-auto bg-n-surface-1 w-full px-6">
    <div :class="fullWidth ? 'w-full pb-12' : 'max-w-5xl mx-auto pb-12'">
      <router-view />
    </div>
  </div>
</template>
