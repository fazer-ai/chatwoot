<script setup>
import KanbanColumn from './KanbanColumn.vue';

defineProps({
  columns: { type: Array, required: true },
  conversationsByStatus: { type: Object, required: true },
});

const emit = defineEmits(['moveCard', 'exportColumn']);
</script>

<template>
  <div class="flex-1 min-h-0 overflow-x-auto">
    <div class="flex gap-4 p-4 h-full min-w-max">
      <KanbanColumn
        v-for="column in columns"
        :key="column.id"
        :column="column"
        :conversations="conversationsByStatus[column.id] || []"
        @move-card="emit('moveCard', $event)"
        @export-column="emit('exportColumn', $event)"
      />
    </div>
  </div>
</template>
