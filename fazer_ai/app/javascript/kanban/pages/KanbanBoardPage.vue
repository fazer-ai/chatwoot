<script setup>
import { computed, ref, watch, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { OnClickOutside } from '@vueuse/components';
import { useMediaQuery } from '@vueuse/core';
import { KANBAN_COLUMN_WIDTH_STYLES } from '../constants';
import { useChannelIcon } from 'dashboard/components-next/icon/provider';
import Button from 'dashboard/components-next/button/Button.vue';
import SelectMenu from 'dashboard/components-next/selectmenu/SelectMenu.vue';
import KanbanBoard from 'kanban/components/KanbanBoard.vue';
import KanbanBoardSwitcher from 'kanban/components/KanbanBoardSwitcher.vue';
import KanbanBoardModal from 'kanban/components/KanbanBoardModal.vue';
import KanbanTaskSortMenu from 'kanban/components/KanbanTaskSortMenu.vue';
import KanbanTaskModal from 'kanban/components/KanbanTaskModal.vue';
import KanbanStepModal from 'kanban/components/KanbanStepModal.vue';
import KanbanDeleteTaskDialog from 'kanban/components/KanbanDeleteTaskDialog.vue';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import kanbanModule from 'kanban/store/modules/kanban';
import { useBoardModal } from 'kanban/composables/useBoardModal';

const router = useRouter();
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const { isAdmin } = useAdmin();
const isLargeScreen = useMediaQuery('(min-width: 1080px)');

const fazerAiSubscription = computed(
  () => store.getters['globalConfig/getFazerAiSubscription']
);
const isFazerAiSubscriptionActive = computed(() => {
  const status = fazerAiSubscription.value?.status;
  return ['active', 'past_due', 'trialing'].includes(status);
});

if (!store.hasModule('kanban')) {
  store.registerModule('kanban', kanbanModule);
}

const preferences = computed(() => store.state.kanban.preferences);
const steps = computed(() => store.getters['kanban/orderedSteps']);
const boards = computed(() => store.state.kanban.boards);
const activeBoard = computed(() => store.getters['kanban/activeBoard']);
const selectedBoardId = computed(() => store.state.kanban.selectedBoardId);
const isLoading = computed(() => store.state.kanban.isLoading);

// Step-based loading state
const stepTasksMap = computed(() => store.getters['kanban/stepTasksMap']);
const stepMetaMap = computed(() => store.getters['kanban/stepMetaMap']);
const stepLoadingMap = computed(() => store.getters['kanban/stepLoadingMap']);
const stepFetchedMap = computed(() => store.getters['kanban/stepFetchedMap']);
// Derive all fetched tasks from stepTasksMap for filter counts
const allFetchedTasks = computed(() => {
  const allTasks = stepTasksMap.value || {};
  return Object.values(allTasks).flat();
});

const activeSort = ref('position');
const activeOrdering = ref('asc');

const showCompleted = ref(false);
const showCancelled = ref(false);

const collapsedStepIds = computed(() => {
  return steps.value
    .filter(step => {
      if (step.inferred_task_status === 'completed' && !showCompleted.value) {
        return true;
      }
      if (step.inferred_task_status === 'cancelled' && !showCancelled.value) {
        return true;
      }
      return false;
    })
    .map(step => step.id);
});

const fetchTasksForStep = (stepId, options = {}) =>
  store.dispatch('kanban/fetchTasksForStep', { stepId, ...options });
const fetchMoreTasksForStep = stepId =>
  store.dispatch('kanban/fetchMoreTasksForStep', stepId);

// Fetch tasks for visible (non-collapsed) steps when they become available
const fetchVisibleStepTasks = async () => {
  const visibleSteps = steps.value.filter(
    step => !collapsedStepIds.value.includes(step.id)
  );

  await Promise.all(
    visibleSteps.map(step => {
      if (!stepFetchedMap.value[step.id]) {
        return fetchTasksForStep(step.id, { page: 1, perPage: 10 });
      }
      return Promise.resolve();
    })
  );
};

const setActiveBoard = (id, filters = {}) => {
  const savedSort = preferences.value.task_sorting?.[id] || {};
  const sort = savedSort.sort || 'position';
  const order = savedSort.order || 'asc';

  return store.dispatch('kanban/setActiveBoard', {
    boardId: id,
    sort,
    order,
    agentId: filters.agentId,
    inboxId: filters.inboxId,
  });
};
const fetchBoards = () => store.dispatch('kanban/fetchBoards');
const createTask = data => store.dispatch('kanban/createTask', data);
const updateTask = data => store.dispatch('kanban/updateTask', data);

const isCountsLoading = ref(false);
const selectedAgentId = ref('all');
const selectedInboxId = ref('all');

const fetchStepsWithFilters = async () => {
  isCountsLoading.value = true;
  try {
    await store.dispatch('kanban/fetchSteps', {
      boardId: selectedBoardId.value,
      agentId: selectedAgentId.value,
      inboxId: selectedInboxId.value,
    });
  } finally {
    isCountsLoading.value = false;
  }
};

const moveTask = ({ task, destinationStepId, insertBeforeTaskId }) =>
  store.dispatch('kanban/moveTask', {
    taskId: task.id,
    destinationStepId,
    insertBeforeTaskId,
    refreshStepId: destinationStepId,
  });
const removeTask = id => store.dispatch('kanban/deleteTask', id);
const createStep = data => store.dispatch('kanban/createStep', data);
const updateStep = data => store.dispatch('kanban/updateStep', data);
const removeStep = data => store.dispatch('kanban/deleteStep', data);

const hasSteps = computed(() => steps.value.length > 0);
const showBoardSwitcher = ref(false);
const showTaskModal = ref(false);
const showStepModal = ref(false);
const selectedTask = ref(null);
const duplicateTask = ref(null);
const selectedStep = ref(null);
const selectedStepId = ref(null);
const isSaving = ref(false);
const isDeleting = ref(false);
const isSavingStep = ref(false);
const isDeletingStep = ref(false);
const showDeleteDialog = ref(false);
const taskToDelete = ref(null);
const isDataLoaded = ref(false);

const onSortChange = async ({ sort, order }) => {
  activeSort.value = sort;
  activeOrdering.value = order;

  // Save sort preferences
  await store.dispatch('kanban/updateTaskSorting', {
    boardId: selectedBoardId.value,
    sort,
    order,
  });

  // Reset step tasks and re-fetch with new sort
  await store.dispatch('kanban/resetStepTasks');
  await fetchVisibleStepTasks();
};

const isDragEnabled = computed(() => activeSort.value === 'position');

const agents = computed(() => activeBoard.value?.assigned_agents || []);
const inboxes = computed(() => activeBoard.value?.assigned_inboxes || []);
const currentUserId = computed(() => store.getters.getCurrentUserID);

const agentOptions = computed(() => {
  const allOption = {
    label: t('KANBAN.FILTERS.ALL_AGENTS'),
    value: 'all',
    icon: 'i-lucide-user',
  };
  const sortedAgents = [...agents.value].sort((a, b) => {
    if (a.id === currentUserId.value) return -1;
    if (b.id === currentUserId.value) return 1;
    return 0;
  });

  const options = sortedAgents.map(agent => {
    const isCurrentUser = agent.id === currentUserId.value;
    const label = isCurrentUser
      ? `${agent.name} (${t('KANBAN.FILTERS.ME')})`
      : agent.name;

    return {
      label,
      value: String(agent.id),
      thumbnail: agent.avatar_url,
    };
  });
  const result = [allOption, ...options];

  if (isAdmin.value) {
    result.push({
      label: t('KANBAN.FILTERS.ASSIGN_AGENT', 'Assign agent'),
      value: 'assign_agent',
      icon: 'i-lucide-plus',
    });
  }

  return result;
});

const inboxOptions = computed(() => {
  const allOption = {
    label: t('KANBAN.FILTERS.ALL_INBOXES'),
    value: 'all',
    icon: 'i-lucide-inbox',
  };

  const options = inboxes.value.map(inbox => {
    return {
      label: inbox.name,
      value: String(inbox.id),
      icon: useChannelIcon(inbox).value,
    };
  });
  const result = [allOption, ...options];

  if (isAdmin.value) {
    result.push({
      label: t('KANBAN.FILTERS.ASSIGN_INBOX', 'Assign inbox'),
      value: 'assign_inbox',
      icon: 'i-lucide-plus',
    });
  }

  return result;
});

const filteredTasksByStep = computed(() => {
  const allTasks = stepTasksMap.value || {};
  const filtered = {};
  Object.keys(allTasks).forEach(stepId => {
    filtered[stepId] = (allTasks[stepId] || []).filter(task => {
      if (selectedAgentId.value !== 'all') {
        const hasAgent = task.assigned_agents.some(
          a => String(a.id) === selectedAgentId.value
        );
        if (!hasAgent) return false;
      }

      if (selectedInboxId.value !== 'all') {
        const hasInbox = task.conversations.some(
          c => String(c.inbox.id) === selectedInboxId.value
        );
        if (!hasInbox) return false;
      }

      if (task.status === 'completed' && !showCompleted.value) return false;
      if (task.status === 'cancelled' && !showCancelled.value) return false;

      return true;
    });
  });
  return filtered;
});

const filteredTotalTasks = computed(() => {
  // Use filtered count from API when available, otherwise use tasks_count
  return steps.value
    .filter(step => !collapsedStepIds.value.includes(step.id))
    .reduce(
      (sum, step) => sum + (step.filtered_tasks_count ?? step.tasks_count ?? 0),
      0
    );
});

// Handle loading more tasks for a step
const onLoadMore = stepId => {
  fetchMoreTasksForStep(stepId);
};

// Handle step expansion - fetch tasks if not yet fetched
const onExpandStep = stepId => {
  if (!stepFetchedMap.value[stepId]) {
    fetchTasksForStep(stepId, { page: 1, perPage: 10 });
  }
};

// const openComplexFilters = () => {
//   // TODO: Implement complex filters
// };

onMounted(() => {
  store.dispatch('agents/get');
  store.dispatch('inboxes/get');
  // Reset so watcher doesn't fire until syncBoardFromRoute completes
  isDataLoaded.value = false;
});

// Watch for steps to be loaded and fetch visible step tasks
watch(
  () => steps.value,
  async newSteps => {
    if (isDataLoaded.value && newSteps.length > 0) {
      await fetchVisibleStepTasks();
    }
  }
);

// When collapsed steps change (user shows completed/cancelled), fetch newly visible steps
watch(
  () => [showCompleted.value, showCancelled.value],
  async () => {
    if (isDataLoaded.value && steps.value.length > 0) {
      await fetchVisibleStepTasks();
    }
  }
);

watch(
  selectedBoardId,
  newBoardId => {
    if (newBoardId) {
      const savedSort = preferences.value.task_sorting?.[newBoardId] || {};
      activeSort.value = savedSort.sort || 'position';
      activeOrdering.value = savedSort.order || 'asc';

      // Reset step tasks when switching boards
      store.dispatch('kanban/resetStepTasks');
    }
  },
  { immediate: true }
);

watch(agents, () => {
  if (selectedAgentId.value === 'all') return;
  const agentExists = agents.value.some(
    agent => String(agent.id) === selectedAgentId.value
  );
  if (!agentExists) {
    selectedAgentId.value = 'all';
  }
});

watch(inboxes, () => {
  if (selectedInboxId.value === 'all') return;
  const inboxExists = inboxes.value.some(
    inbox => String(inbox.id) === selectedInboxId.value
  );
  if (!inboxExists) {
    selectedInboxId.value = 'all';
  }
});

watch(
  [selectedAgentId, selectedInboxId, showCompleted, showCancelled],
  async (
    [newAgentId, newInboxId, newShowCompleted, newShowCancelled],
    [oldAgentId, oldInboxId]
  ) => {
    if (!selectedBoardId.value || !isDataLoaded.value) return;

    store.dispatch('kanban/updateBoardFilters', {
      boardId: selectedBoardId.value,
      agentId: newAgentId,
      inboxId: newInboxId,
      showCompleted: newShowCompleted,
      showCancelled: newShowCancelled,
    });

    // Re-fetch steps and tasks when agent/inbox filter changes
    if (newAgentId !== oldAgentId || newInboxId !== oldInboxId) {
      // Reset tasks first so skeletons appear immediately
      await store.dispatch('kanban/resetStepTasks');
      // Then fetch steps (for counts) and tasks
      await fetchStepsWithFilters();
      await fetchVisibleStepTasks();
    }
  }
);

const activeBoardName = computed(
  () => activeBoard.value?.name || t('KANBAN.BOARDS.FALLBACK_NAME')
);

const closeBoardSwitcher = () => {
  showBoardSwitcher.value = false;
};

const toggleBoardSwitcher = () => {
  showBoardSwitcher.value = !showBoardSwitcher.value;
};

const navigateToBoard = boardId => {
  if (!boardId || !route.params.accountId) return;
  const id = Number(boardId);

  if (Number(route.params.boardId) !== id) {
    router.replace({
      name: 'kanban_board_show',
      params: {
        accountId: route.params.accountId,
        boardId: id,
      },
    });
  } else if (selectedBoardId.value !== id) {
    const boardFilters = preferences.value.board_filters || {};
    const savedFilters = boardFilters[id] || {};
    const agentId = savedFilters.agent_id || 'all';
    const inboxId = savedFilters.inbox_id || 'all';
    selectedAgentId.value = agentId;
    selectedInboxId.value = inboxId;
    showCompleted.value = savedFilters.show_completed || false;
    showCancelled.value = savedFilters.show_cancelled || false;
    setActiveBoard(id, { agentId, inboxId });
  }

  closeBoardSwitcher();
};

const openCreateModal = (stepId = null) => {
  const validStepId =
    typeof stepId === 'number' || typeof stepId === 'string' ? stepId : null;

  selectedTask.value = null;
  duplicateTask.value = null;
  selectedStepId.value = validStepId || steps.value[0]?.id;

  if (route.name !== 'kanban_task_create') {
    router.push({
      name: 'kanban_task_create',
      params: {
        accountId: route.params.accountId,
        boardId: route.params.boardId,
      },
    });
  }

  showTaskModal.value = true;
};

const openEditModal = task => {
  selectedTask.value = task;
  duplicateTask.value = null;
  selectedStepId.value = task.board_step_id;

  if (
    route.name !== 'kanban_task_show' ||
    Number(route.params.taskId) !== task.id
  ) {
    router.push({
      name: 'kanban_task_show',
      params: {
        accountId: route.params.accountId,
        boardId: route.params.boardId,
        taskId: task.id,
      },
    });
  }

  showTaskModal.value = true;
};

const openDuplicateModal = task => {
  selectedTask.value = null;
  duplicateTask.value = task;
  selectedStepId.value = task.board_step_id;

  if (route.name !== 'kanban_task_create') {
    router.push({
      name: 'kanban_task_create',
      params: {
        accountId: route.params.accountId,
        boardId: route.params.boardId,
      },
    });
  }

  showTaskModal.value = true;
};

const openDeleteDialog = task => {
  taskToDelete.value = task;
  showDeleteDialog.value = true;
};

const closeDeleteDialog = () => {
  showDeleteDialog.value = false;
  taskToDelete.value = null;
};

const confirmDeleteTask = async () => {
  if (!taskToDelete.value) return;

  isDeleting.value = true;
  try {
    await removeTask(taskToDelete.value.id);
    closeDeleteDialog();
  } catch {
    // Handle error
  } finally {
    isDeleting.value = false;
  }
};

const openCreateStepModal = () => {
  selectedStep.value = null;
  showStepModal.value = true;
};

const openStepModal = step => {
  selectedStep.value = step;
  showStepModal.value = true;
};

const closeModal = () => {
  showTaskModal.value = false;
  selectedTask.value = null;
  duplicateTask.value = null;
  selectedStepId.value = null;

  if (route.name !== 'kanban_board_show') {
    router.push({
      name: 'kanban_board_show',
      params: {
        accountId: route.params.accountId,
        boardId: route.params.boardId,
      },
    });
  }
};

const closeStepModal = () => {
  showStepModal.value = false;
  selectedStep.value = null;
};

const syncBoardFromRoute = async () => {
  const boardId = route.params.boardId ? Number(route.params.boardId) : null;
  const hasMatchingBoard = boards.value.some(board => board.id === boardId);

  if (boardId && hasMatchingBoard) {
    // Only fetch data if we're switching to a different board or data isn't loaded
    const needsDataLoad =
      selectedBoardId.value !== boardId || !isDataLoaded.value;
    if (needsDataLoad) {
      isDataLoaded.value = false;

      const boardFilters = preferences.value.board_filters || {};
      const savedFilters = boardFilters[boardId] || {};
      const agentId = savedFilters.agent_id || 'all';
      const inboxId = savedFilters.inbox_id || 'all';
      selectedAgentId.value = agentId;
      selectedInboxId.value = inboxId;
      showCompleted.value = savedFilters.show_completed || false;
      showCancelled.value = savedFilters.show_cancelled || false;

      await setActiveBoard(boardId, { agentId, inboxId });
      isDataLoaded.value = true;
      await fetchVisibleStepTasks();
    }

    const taskId = route.params.taskId ? Number(route.params.taskId) : null;
    if (route.name === 'kanban_task_create') {
      if (!showTaskModal.value) {
        openCreateModal();
      }
    } else if (taskId && route.name === 'kanban_task_show') {
      const task = allFetchedTasks.value.find(tt => tt.id === taskId);
      if (task) {
        if (!showTaskModal.value || selectedTask.value?.id !== taskId) {
          selectedTask.value = task;
          duplicateTask.value = null;
          selectedStepId.value = task.board_step_id;
          showTaskModal.value = true;
        }
      } else {
        router.replace({
          name: 'kanban_board_show',
          params: {
            accountId: route.params.accountId,
            boardId: route.params.boardId,
          },
        });
      }
    }
    return;
  }

  router.replace({
    name: 'kanban_list',
    params: { accountId: route.params.accountId },
  });
};

onMounted(async () => {
  if (!isFazerAiSubscriptionActive.value) {
    router.replace({
      name: 'kanban_list',
      params: { accountId: route.params.accountId },
    });
    return;
  }

  await fetchBoards();
  await syncBoardFromRoute();
});

const saveTask = async data => {
  isSaving.value = true;

  try {
    if (data.task.id) {
      await updateTask({
        id: data.task.id,
        task: data.task,
      });
    } else {
      await createTask(data);
    }
    closeModal();
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('KANBAN.MODAL.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const saveStep = async data => {
  isSavingStep.value = true;
  try {
    if (data.id) {
      await updateStep({
        boardId: selectedBoardId.value,
        stepId: data.id,
        step: data,
      });
    } else {
      await createStep({
        boardId: selectedBoardId.value,
        step: data,
      });
    }
    closeStepModal();
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('KANBAN.MODAL.SAVE_ERROR'));
  } finally {
    isSavingStep.value = false;
  }
};

const deleteStep = async id => {
  isDeletingStep.value = true;
  try {
    await removeStep({
      boardId: selectedBoardId.value,
      stepId: id,
    });
    closeStepModal();
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('KANBAN.MODAL.DELETE_ERROR'));
  } finally {
    isDeletingStep.value = false;
  }
};

const deleteTask = async id => {
  isDeleting.value = true;
  try {
    await removeTask(id);
    closeModal();
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('KANBAN.MODAL.DELETE_ERROR'));
  } finally {
    isDeleting.value = false;
  }
};

const navigateToSettings = (hash = '') => {
  if (!selectedBoardId.value || !route.params.accountId) return;
  router.push({
    name: 'kanban_board_settings',
    params: {
      accountId: route.params.accountId,
      boardId: selectedBoardId.value,
    },
    hash,
  });
};

const handleAgentSelect = value => {
  if (value === 'assign_agent') {
    navigateToSettings('#board-agents');
    return;
  }
  selectedAgentId.value = value;
};

const handleInboxSelect = value => {
  if (value === 'assign_inbox') {
    navigateToSettings('#board-inboxes');
    return;
  }
  selectedInboxId.value = value;
};

const onEnableFilter = status => {
  if (status === 'completed') {
    showCompleted.value = true;
  } else if (status === 'cancelled') {
    showCancelled.value = true;
  }
};

const {
  showBoardModal,
  isSavingBoard,
  openBoardModal,
  closeBoardModal,
  saveBoard,
} = useBoardModal({
  onSuccess: newBoard => {
    if (newBoard?.id) {
      navigateToBoard(newBoard.id);
    }
  },
  onError: error => {
    useAlert(
      parseAPIErrorResponse(error) || t('KANBAN.BOARD_MODAL.CREATE_ERROR')
    );
  },
});

watch(
  () => [route.params.boardId, route.params.taskId, route.name],
  async () => {
    await syncBoardFromRoute();
  },
  { immediate: false }
);

watch(
  () => boards.value.length,
  async () => {
    if (!isDataLoaded.value) return;
    closeBoardSwitcher();
    await syncBoardFromRoute();
  }
);

const isStepDeletable = computed(() => {
  if (!selectedStep.value) return true;
  return steps.value.length > 1;
});

const skeletonColumnStyle = {
  ...KANBAN_COLUMN_WIDTH_STYLES,
};

const selectedAgentLabel = computed(() => {
  const selected = agentOptions.value.find(
    o => o.value === selectedAgentId.value
  );
  return selected ? selected.label : t('KANBAN.FILTERS.ALL_AGENTS');
});

const selectedInboxLabel = computed(() => {
  const selected = inboxOptions.value.find(
    o => o.value === selectedInboxId.value
  );
  return selected ? selected.label : t('KANBAN.FILTERS.ALL_INBOXES');
});

const selectedAgentThumbnail = computed(() => {
  const selected = agentOptions.value.find(
    o => o.value === selectedAgentId.value
  );
  return selected ? selected.thumbnail : null;
});

const selectedAgentIcon = computed(() => {
  const selected = agentOptions.value.find(
    o => o.value === selectedAgentId.value
  );
  return selected ? selected.icon : null;
});

const selectedInboxIcon = computed(() => {
  const selected = inboxOptions.value.find(
    o => o.value === selectedInboxId.value
  );
  return selected ? selected.icon : null;
});
</script>

<template>
  <div class="flex h-full w-full flex-col bg-n-background font-inter">
    <div class="w-full flex justify-center px-6 pt-8 pb-4">
      <div class="w-full max-w-7xl">
        <SettingsLayout :is-loading="false">
          <template #header>
            <div class="flex items-center justify-between w-full gap-4">
              <div class="flex items-center gap-2 min-w-0">
                <div class="group relative flex-shrink-0">
                  <OnClickOutside @trigger="closeBoardSwitcher">
                    <Button
                      icon="i-lucide-chevron-down"
                      variant="ghost"
                      color="slate"
                      size="xs"
                      class="rounded-md hover:bg-n-slate-3 group-hover:bg-n-slate-3"
                      @click="toggleBoardSwitcher"
                    />

                    <KanbanBoardSwitcher
                      v-if="showBoardSwitcher"
                      class="absolute top-9"
                      :boards="boards"
                      :active-board-id="selectedBoardId"
                      @create-board="openBoardModal"
                      @close="closeBoardSwitcher"
                    />
                  </OnClickOutside>
                </div>
                <h1
                  class="text-sm font-medium tracking-tight text-n-slate-12 truncate max-w-[200px]"
                >
                  {{ activeBoardName }}
                </h1>
                <div class="flex items-center gap-1">
                  <span
                    v-if="!isLoading"
                    class="flex h-5 min-w-[1.25rem] items-center justify-center rounded-full bg-n-slate-3 px-2 text-xs font-medium text-n-slate-11"
                  >
                    <span
                      v-if="isCountsLoading"
                      class="w-3 h-3 rounded-full bg-n-slate-5 animate-pulse"
                    />
                    <template v-else>{{ filteredTotalTasks }}</template>
                  </span>
                </div>
              </div>
              <div class="flex items-center gap-2">
                <Button
                  v-tooltip="
                    showCompleted
                      ? t('KANBAN.FILTERS.HIDE_STATUS', {
                          status: t('KANBAN.STATUS.COMPLETED'),
                        })
                      : t('KANBAN.FILTERS.SHOW_STATUS', {
                          status: t('KANBAN.STATUS.COMPLETED'),
                        })
                  "
                  variant="ghost"
                  :color="showCompleted ? 'teal' : 'slate'"
                  size="sm"
                  icon="i-lucide-check-circle-2"
                  @click="showCompleted = !showCompleted"
                />
                <Button
                  v-tooltip="
                    showCancelled
                      ? t('KANBAN.FILTERS.HIDE_STATUS', {
                          status: t('KANBAN.STATUS.CANCELLED'),
                        })
                      : t('KANBAN.FILTERS.SHOW_STATUS', {
                          status: t('KANBAN.STATUS.CANCELLED'),
                        })
                  "
                  variant="ghost"
                  :color="showCancelled ? 'ruby' : 'slate'"
                  size="sm"
                  icon="i-lucide-x-circle"
                  @click="showCancelled = !showCancelled"
                />
                <div class="w-px h-4 bg-n-slate-4 mx-1" />
                <SelectMenu
                  :model-value="selectedAgentId"
                  :options="agentOptions"
                  :label="selectedAgentLabel"
                  :hide-label="!isLargeScreen"
                  :thumbnail="selectedAgentThumbnail"
                  :icon="selectedAgentIcon"
                  show-avatar
                  sub-menu-position="bottom"
                  max-width="max-w-56"
                  @update:model-value="handleAgentSelect"
                />
                <SelectMenu
                  :model-value="selectedInboxId"
                  :options="inboxOptions"
                  :label="selectedInboxLabel"
                  :hide-label="!isLargeScreen"
                  :icon="selectedInboxIcon"
                  show-avatar
                  sub-menu-position="bottom"
                  max-width="max-w-56"
                  @update:model-value="handleInboxSelect"
                />
                <KanbanTaskSortMenu
                  :active-sort="activeSort"
                  :active-ordering="activeOrdering"
                  @update:sort="onSortChange"
                />
                <!-- <Button
                  icon="i-lucide-filter"
                  variant="ghost"
                  color="slate"
                  size="sm"
                  @click="openComplexFilters"
                /> -->
                <router-link
                  v-if="selectedBoardId && isAdmin"
                  :to="{
                    name: 'kanban_board_settings',
                    params: {
                      accountId: route.params.accountId,
                      boardId: selectedBoardId,
                    },
                  }"
                  class="flex items-center"
                >
                  <Button
                    icon="i-lucide-settings"
                    variant="ghost"
                    color="slate"
                    size="sm"
                  />
                </router-link>
                <Button
                  :disabled="!hasSteps"
                  icon="i-lucide-plus"
                  size="sm"
                  :label="t('KANBAN.ADD_TASK')"
                  :hide-label="!isLargeScreen"
                  @click="openCreateModal"
                />
              </div>
            </div>
          </template>
        </SettingsLayout>
      </div>
    </div>
    <div class="flex-1 overflow-x-auto scrollbar-custom">
      <div class="flex justify-start px-6 min-w-full h-full">
        <div class="w-full h-full">
          <div
            v-if="isLoading"
            class="flex h-full w-full gap-4 px-1 pb-4 animate-pulse overflow-hidden"
          >
            <div
              v-for="(taskCount, index) in [3, 2, 5, 1, 0]"
              :key="index"
              class="flex h-full flex-shrink-0 flex-col overflow-hidden rounded-xl shadow-sm outline-1 outline outline-n-container"
              :style="skeletonColumnStyle"
            >
              <div
                class="flex items-center justify-between px-4 py-3 bg-n-slate-3"
              >
                <div class="flex items-center gap-2">
                  <div class="h-5 w-24 bg-n-slate-4 rounded" />
                  <div class="h-5 w-6 bg-n-slate-4 rounded-full" />
                </div>
                <div class="h-8 w-8 bg-n-slate-4 rounded-md" />
              </div>

              <div class="flex-1 p-2 bg-n-slate-1 flex flex-col gap-2">
                <div
                  v-for="taskIndex in taskCount"
                  :key="taskIndex"
                  class="p-3 bg-n-background border border-n-slate-3 rounded-lg flex flex-col gap-3 shadow-sm"
                >
                  <div class="h-5 w-3/4 bg-n-slate-3 rounded" />
                  <div class="flex justify-between items-center">
                    <div class="h-4 w-16 bg-n-slate-3 rounded" />
                    <div class="h-6 w-6 rounded-full bg-n-slate-3" />
                  </div>
                </div>
              </div>
            </div>
          </div>
          <KanbanBoard
            v-else
            :steps="steps"
            :tasks-by-step="filteredTasksByStep"
            :collapsed-step-ids="collapsedStepIds"
            :is-drag-enabled="isDragEnabled"
            :step-loading-map="stepLoadingMap"
            :step-meta-map="stepMetaMap"
            :step-fetched-map="stepFetchedMap"
            :is-counts-loading="isCountsLoading"
            @add-task="openCreateModal"
            @edit-task="openEditModal"
            @duplicate-task="openDuplicateModal"
            @delete-task="openDeleteDialog"
            @edit-step="openStepModal"
            @add-step="openCreateStepModal"
            @update-task="saveTask"
            @move-task="moveTask"
            @enable-filter="onEnableFilter"
            @load-more="onLoadMore"
            @expand-step="onExpandStep"
          />
        </div>
      </div>
    </div>
    <KanbanTaskModal
      v-if="showTaskModal"
      :show="showTaskModal"
      :task="selectedTask"
      :duplicate-task="duplicateTask"
      :step-id="selectedStepId"
      :steps="steps"
      :board-name="activeBoardName"
      :board-id="activeBoard?.id"
      :is-saving="isSaving"
      :is-deleting="isDeleting"
      :board-agents="activeBoard?.assigned_agents || []"
      @close="closeModal"
      @save="saveTask"
      @delete="deleteTask"
    />
    <KanbanStepModal
      v-if="showStepModal"
      :show="showStepModal"
      :step="selectedStep"
      :board-name="activeBoardName"
      :is-saving="isSavingStep"
      :is-deleting="isDeletingStep"
      :can-delete="isStepDeletable"
      @close="closeStepModal"
      @save="saveStep"
      @delete="deleteStep"
    />
    <KanbanDeleteTaskDialog
      :show="showDeleteDialog"
      :task-title="taskToDelete?.title"
      :is-deleting="isDeleting"
      @confirm="confirmDeleteTask"
      @close="closeDeleteDialog"
    />
    <KanbanBoardModal
      v-if="showBoardModal"
      :show="showBoardModal"
      :is-saving="isSavingBoard"
      @close="closeBoardModal"
      @save="saveBoard"
    />
  </div>
</template>

<style scoped>
:deep(main) {
  @apply flex-1 flex flex-col min-h-0;
}
</style>
