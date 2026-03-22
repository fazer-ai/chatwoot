<script setup>
// No props needed - simple presentational component
</script>

<template>
  <div class="space-y-4 px-4 py-3">
    <div v-for="i in 2" :key="i" class="flex items-start gap-3 animate-pulse">
      <div class="size-8 flex-shrink-0 rounded-full bg-n-slate-4" />
      <div class="flex-1 space-y-2">
        <div class="flex items-center gap-2">
          <div class="h-3 w-24 rounded bg-n-slate-4" />
          <div class="h-2.5 w-12 rounded bg-n-slate-3" />
        </div>
        <div
          class="h-3 rounded bg-n-slate-4"
          :class="i % 2 === 0 ? 'w-3/4' : 'w-full'"
        />
        <div v-if="i % 3 === 0" class="h-3 w-1/2 rounded bg-n-slate-3" />
      </div>
    </div>
  </div>
</template>
