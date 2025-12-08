<script setup>
import { useI18n } from 'vue-i18n';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { KANBAN_COLUMN_WIDTH_STYLES } from '../constants';
import KanbanColumn from './KanbanColumn.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  steps: {
    type: Array,
    default: () => [],
  },
  tasksByStep: {
    type: Object,
    default: () => ({}),
  },
  allTasksByStep: {
    type: Object,
    default: () => ({}),
  },
  collapsedStepIds: {
    type: Array,
    default: () => [],
  },
  isDragEnabled: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits([
  'addTask',
  'editTask',
  'deleteTask',
  'duplicateTask',
  'editStep',
  'addStep',
  'updateTask',
  'moveTask',
  'enableFilter',
]);

const { t } = useI18n();
const { isAdmin } = useAdmin();

const resolveTasks = stepId => props.tasksByStep[stepId] || [];
const resolveAllTasks = stepId => props.allTasksByStep[stepId] || [];
const isStepCollapsed = stepId => props.collapsedStepIds.includes(stepId);

const onEnableFilter = status => {
  emit('enableFilter', status);
};

const onAddTask = stepId => {
  emit('addTask', stepId);
};

const onEditTask = task => {
  emit('editTask', task);
};

const onDuplicateTask = task => {
  emit('duplicateTask', task);
};

const onDeleteTask = task => {
  emit('deleteTask', task);
};

const onUpdateTask = task => {
  emit('updateTask', task);
};

const onMoveTask = payload => {
  emit('moveTask', payload);
};

const onEditStep = step => {
  emit('editStep', step);
};

const ghostStepStyles = {
  ...KANBAN_COLUMN_WIDTH_STYLES,
  flexShrink: 0,
};
</script>

<template>
  <div class="flex h-full w-full gap-4 px-1 pb-4">
    <KanbanColumn
      v-for="step in steps"
      :key="step.id"
      :step="step"
      :all-steps="steps"
      :tasks="resolveTasks(step.id)"
      :is-drag-enabled="isDragEnabled"
      :is-collapsed="isStepCollapsed(step.id)"
      :total-task-count="resolveAllTasks(step.id).length"
      @add-task="onAddTask"
      @edit-task="onEditTask"
      @duplicate-task="onDuplicateTask"
      @delete-task="onDeleteTask"
      @edit-step="onEditStep"
      @update-task="onUpdateTask"
      @move-task="onMoveTask"
      @enable-filter="onEnableFilter"
    />
    <div
      v-if="isAdmin"
      class="flex flex-col items-center justify-center rounded-xl border-2 border-dashed border-n-slate-3 bg-n-slate-1 hover:border-n-slate-4 hover:bg-n-slate-2 transition-colors cursor-pointer"
      :style="ghostStepStyles"
      @click="$emit('addStep')"
    >
      <Button
        variant="outline"
        icon="i-lucide-plus"
        @click.stop="$emit('addStep')"
      >
        {{ t('KANBAN.ADD_STEP') }}
      </Button>
    </div>
  </div>
</template>
