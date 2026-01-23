<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { getContrastingTextColor } from '@chatwoot/utils';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { useAdmin } from 'dashboard/composables/useAdmin';
import Draggable from 'vuedraggable';
import { KANBAN_COLUMN_WIDTH_STYLES } from '../constants';
import KanbanTaskCard from './KanbanTaskCard.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import IntersectionObserver from 'dashboard/components/IntersectionObserver.vue';

const props = defineProps({
  step: {
    type: Object,
    required: true,
  },
  tasks: {
    type: Array,
    default: () => [],
  },
  allSteps: {
    type: Array,
    default: () => [],
  },
  isDragEnabled: {
    type: Boolean,
    default: true,
  },
  isCollapsed: {
    type: Boolean,
    default: false,
  },
  totalTaskCount: {
    type: Number,
    default: 0,
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  hasMore: {
    type: Boolean,
    default: false,
  },
  isFetched: {
    type: Boolean,
    default: false,
  },
  isCountLoading: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'addTask',
  'editTask',
  'deleteTask',
  'duplicateTask',
  'editStep',
  'updateTask',
  'moveTask',
  'enableFilter',
  'loadMore',
]);
// Computed to differentiate initial loading vs loading more
const isInitialLoading = computed(() => props.isLoading && !props.isFetched);
const isLoadingMore = computed(() => props.isLoading && props.isFetched);

const { t } = useI18n();
const { formatMessage } = useMessageFormatter();
const { isAdmin } = useAdmin();

const internalTasks = ref([...props.tasks]);
const scrollContainerRef = ref(null);

const intersectionObserverOptions = computed(() => ({
  root: scrollContainerRef.value,
  rootMargin: '0px 0px 300px 0px',
  threshold: 0.1,
}));

const onLoadMore = () => {
  if (props.hasMore && !props.isLoading && props.tasks.length > 0) {
    emit('loadMore', props.step.id);
  }
};

watch(
  () => props.tasks,
  value => {
    internalTasks.value = [...value];
  }
);

const localTasks = computed({
  get: () => internalTasks.value,
  set: value => {
    internalTasks.value = value;
    const movedTask = value.find(task => task.board_step_id !== props.step.id);

    if (movedTask) {
      const index = value.indexOf(movedTask);
      const beforeTask = index < value.length - 1 ? value[index + 1] : null;
      const insertBeforeTaskId = beforeTask ? beforeTask.id : null;

      emit('moveTask', {
        task: movedTask,
        destinationStepId: props.step.id,
        insertBeforeTaskId,
      });
    }
  },
});

const onChange = event => {
  if (event.moved) {
    const { element, newIndex } = event.moved;
    const newOrder = [...internalTasks.value];

    const beforeTask =
      newIndex < newOrder.length - 1 ? newOrder[newIndex + 1] : null;
    const insertBeforeTaskId = beforeTask ? beforeTask.id : null;

    emit('moveTask', {
      task: element,
      destinationStepId: props.step.id,
      insertBeforeTaskId,
    });
  }
};

const headerTextColor = computed(() => {
  const contrastColor = getContrastingTextColor(props.step.color);
  return `color-mix(in srgb, ${props.step.color}, ${contrastColor} 80%)`;
});

const descriptionTextColor = computed(() => {
  const contrastColor = getContrastingTextColor(props.step.color);
  return `color-mix(in srgb, ${props.step.color}, ${contrastColor} 90%)`;
});

const statusIcon = computed(() => {
  if (props.step.inferred_task_status === 'completed')
    return 'i-lucide-check-circle-2';
  if (props.step.inferred_task_status === 'cancelled')
    return 'i-lucide-x-circle';
  return null;
});

const statusIconColor = computed(() => {
  if (props.step.inferred_task_status === 'completed') return 'text-n-teal-11';
  if (props.step.inferred_task_status === 'cancelled') return 'text-n-ruby-11';
  return '';
});

const statusIconBgColor = computed(() => {
  const contrastColor = getContrastingTextColor(props.step.color);
  return `color-mix(in srgb, ${props.step.color}, ${contrastColor} 30%)`;
});

const statusTooltip = computed(() => {
  if (props.step.inferred_task_status === 'completed')
    return t('KANBAN.STATUS.COMPLETED');
  if (props.step.inferred_task_status === 'cancelled')
    return t('KANBAN.STATUS.CANCELLED');
  return '';
});

const displayedTaskCount = computed(() => {
  return props.totalTaskCount;
});

const containerStyles = computed(() => {
  if (props.isCollapsed) {
    return {
      '--step-color': props.step.color,
      width: '48px',
      minWidth: '48px',
      maxWidth: '48px',
    };
  }
  return {
    ...KANBAN_COLUMN_WIDTH_STYLES,
    '--step-color': props.step.color,
  };
});

const headerStyles = {
  backgroundColor: 'var(--step-color)',
};

const bodyStyles = {
  backgroundColor: 'color-mix(in srgb, var(--step-color), transparent 92%)',
};

const badgeStyles = computed(() => ({
  backgroundColor: `color-mix(in srgb, ${props.step.color}, black 20%)`,
}));

const skeletonStyles = computed(() => ({
  backgroundColor: headerTextColor.value,
  opacity: 0.5,
}));

const collapsedStyles = computed(() => ({
  '--step-color': props.step.color,
  backgroundColor: props.step.color,
  width: '48px',
}));

const verticalTextStyles = computed(() => ({
  color: headerTextColor.value,
  writingMode: 'vertical-lr',
  textOrientation: 'mixed',
}));

const onEnableFilter = () => {
  emit('enableFilter', props.step.inferred_task_status);
};

const enableFilterTooltip = computed(() => {
  if (props.step.inferred_task_status === 'completed') {
    return t('KANBAN.FILTERS.SHOW_STATUS', {
      status: t('KANBAN.STATUS.COMPLETED'),
    });
  }
  if (props.step.inferred_task_status === 'cancelled') {
    return t('KANBAN.FILTERS.SHOW_STATUS', {
      status: t('KANBAN.STATUS.CANCELLED'),
    });
  }
  return '';
});

const onCollapsedAdd = evt => {
  // eslint-disable-next-line no-underscore-dangle
  const task = evt.item.__draggable_context?.element;
  if (task) {
    emit('moveTask', {
      task,
      destinationStepId: props.step.id,
      insertBeforeTaskId: null,
    });
  }
};

const onAddTask = () => {
  emit('addTask', props.step.id);
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

const onEditStep = () => {
  emit('editStep', props.step);
};
</script>

<template>
  <Draggable
    v-if="isCollapsed"
    :model-value="[]"
    tag="section"
    animation="0"
    group="tasks"
    item-key="id"
    class="mt-px flex-shrink-0 self-start flex flex-col items-center py-3 px-1 rounded-xl shadow-sm outline-1 outline outline-n-container min-h-[200px]"
    ghost-class="!hidden"
    :sort="false"
    :style="collapsedStyles"
    @add="onCollapsedAdd"
  >
    <template #header>
      <span
        v-if="statusIcon"
        v-tooltip="statusTooltip"
        class="flex-shrink-0 mb-2 size-5 flex items-center justify-center rounded-full"
        :style="{ backgroundColor: statusIconBgColor }"
      >
        <span
          :class="[statusIcon, statusIconColor || '']"
          class="size-3.5"
          :style="statusIconColor ? {} : { color: headerTextColor }"
        />
      </span>
      <span
        class="flex h-5 min-w-[1.25rem] flex-shrink-0 items-center justify-center rounded-full px-1 text-xs font-medium mb-3"
        :style="{ ...badgeStyles, color: headerTextColor }"
      >
        <span
          v-if="isCountLoading"
          class="w-3 h-3 rounded-full animate-pulse"
          :style="skeletonStyles"
        />
        <template v-else>{{ totalTaskCount }}</template>
      </span>
      <h3
        class="text-sm font-semibold whitespace-nowrap py-2 flex-1"
        :style="verticalTextStyles"
      >
        {{ step.name }}
      </h3>
    </template>
    <template #item="{ element }">
      <div :key="element.id" class="hidden" />
    </template>
    <template #footer>
      <Button
        v-tooltip="enableFilterTooltip"
        variant="ghost"
        size="sm"
        icon="i-lucide-eye"
        class="mt-3 h-8 w-8 rounded hover:bg-white/20"
        :style="{ color: headerTextColor }"
        @click="onEnableFilter"
      />
    </template>
  </Draggable>

  <section
    v-else
    class="mt-px flex h-full flex-shrink-0 flex-col overflow-hidden rounded-xl bg-n-surface-0 shadow-sm outline-1 outline outline-n-container"
    :style="containerStyles"
  >
    <header
      class="relative z-10 px-4 py-3 shadow-sm"
      :style="{ ...headerStyles, color: headerTextColor }"
    >
      <div class="flex items-center justify-between gap-2">
        <div class="flex flex-1 items-center gap-2 min-w-0">
          <span
            v-if="statusIcon"
            v-tooltip="statusTooltip"
            class="flex-shrink-0 size-5 flex items-center justify-center rounded-full"
            :style="{ backgroundColor: statusIconBgColor }"
          >
            <span
              :class="[statusIcon, statusIconColor || '']"
              class="size-3.5"
              :style="statusIconColor ? {} : { color: headerTextColor }"
            />
          </span>
          <h3
            class="text-sm font-semibold break-words min-w-0"
            :style="{ color: headerTextColor }"
          >
            {{ step.name }}
          </h3>
          <span
            class="flex h-5 min-w-[1.25rem] flex-shrink-0 items-center justify-center rounded-full px-1 text-xs font-medium"
            :style="{ ...badgeStyles, color: headerTextColor }"
          >
            <span
              v-if="isCountLoading"
              class="w-3 h-3 rounded-full animate-pulse"
              :style="skeletonStyles"
            />
            <template v-else>{{ displayedTaskCount }}</template>
          </span>
        </div>
        <div class="flex flex-shrink-0 items-center gap-1">
          <Button
            v-if="isAdmin"
            variant="ghost"
            size="xs"
            icon="i-lucide-settings"
            class="h-6 w-6 rounded hover:bg-white/20 [&_span]:size-4"
            :style="{ color: headerTextColor }"
            @click="onEditStep"
          />
          <Button
            variant="ghost"
            size="xs"
            icon="i-lucide-plus"
            class="h-6 w-6 rounded hover:bg-white/20 [&_span]:size-4"
            :style="{ color: headerTextColor }"
            @click="onAddTask"
          />
        </div>
      </div>
      <div
        v-if="step.description"
        v-dompurify-html="formatMessage(step.description, false)"
        class="mt-1 text-xs opacity-80 break-words [&_p]:my-0 [&_ul]:my-0 [&_ol]:my-0 [&_li]:my-0 [&_ul]:pl-4 [&_ol]:pl-4 [&_ul]:list-disc [&_ol]:list-decimal"
        :style="{ color: descriptionTextColor }"
      />
    </header>

    <div
      ref="scrollContainerRef"
      class="kanban-column-body flex flex-col flex-1 overflow-y-auto px-2 py-2 scrollbar-custom"
      :style="bodyStyles"
    >
      <!-- Card skeletons during initial loading -->
      <div v-if="isInitialLoading" class="space-y-2 flex-1 animate-pulse">
        <div
          v-for="i in 10"
          :key="i"
          class="p-3 bg-n-background border border-n-slate-3 rounded-lg flex flex-col gap-3 shadow-sm"
        >
          <div class="h-5 w-3/4 bg-n-slate-3 rounded" />
          <div class="flex justify-between items-center">
            <div class="h-4 w-16 bg-n-slate-3 rounded" />
            <div class="h-6 w-6 rounded-full bg-n-slate-3" />
          </div>
        </div>
      </div>

      <!-- Actual task list when loaded -->
      <Draggable
        v-else
        v-model="localTasks"
        animation="200"
        group="tasks"
        item-key="id"
        class="space-y-2 flex-1 min-h-[10px]"
        ghost-class="ghost"
        :sort="isDragEnabled"
        @change="onChange"
      >
        <template #item="{ element }">
          <KanbanTaskCard
            :task="element"
            :all-steps="allSteps"
            @edit="onEditTask"
            @duplicate="onDuplicateTask"
            @delete="onDeleteTask"
            @update="onUpdateTask"
            @move="onMoveTask"
          />
        </template>
        <template #footer>
          <!-- Skeleton cards while loading more -->
          <div
            v-if="isLoadingMore && tasks.length > 0"
            class="py-2 space-y-2 animate-pulse"
          >
            <div
              v-for="i in 5"
              :key="i"
              class="p-3 bg-n-background border border-n-slate-3 rounded-lg flex flex-col gap-3 shadow-sm"
            >
              <div class="h-5 w-3/4 bg-n-slate-3 rounded" />
              <div class="flex justify-between items-center">
                <div class="h-4 w-16 bg-n-slate-3 rounded" />
                <div class="h-6 w-6 rounded-full bg-n-slate-3" />
              </div>
            </div>
          </div>
          <!-- Intersection observer for infinite scroll -->
          <IntersectionObserver
            v-else-if="hasMore && tasks.length > 0"
            :options="intersectionObserverOptions"
            @observed="onLoadMore"
          />
          <div class="mt-2">
            <Button
              variant="ghost"
              color="slate"
              size="sm"
              class="w-full justify-start text-n-slate-11 hover:text-n-slate-12"
              icon="i-lucide-plus"
              @click="onAddTask"
            >
              {{ t('KANBAN.COLUMN.ADD_TASK') }}
            </Button>
          </div>
        </template>
      </Draggable>
    </div>
  </section>
</template>
