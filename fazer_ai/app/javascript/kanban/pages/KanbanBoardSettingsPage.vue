<script setup>
import { computed, ref, onMounted, watch, nextTick } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import Draggable from 'vuedraggable';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import KanbanStepModal from 'kanban/components/KanbanStepModal.vue';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import kanbanModule from 'kanban/store/modules/kanban';

const router = useRouter();
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const { isAdmin } = useAdmin();

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

const boardId = computed(() => Number(route.params.boardId));
const activeBoard = computed(() => store.getters['kanban/activeBoard']);
const steps = computed(() => store.getters['kanban/orderedSteps']);
const agents = computed(() => store.state.agents.records);
const inboxes = computed(() => store.getters['inboxes/getInboxes']);

const agentOptions = computed(() =>
  agents.value.map(agent => ({
    id: agent.id,
    name: agent.name,
    avatar_url: agent.thumbnail,
    availability_status: agent.availability_status,
  }))
);

const boardName = ref('');
const boardDescription = ref('');
const headerBoardName = ref('');
const selectedAgents = ref([]);
const selectedInboxes = ref([]);
const autoCreateTaskForConversation = ref(false);
const autoAssignTaskToAgent = ref(false);
const syncTaskAndConversationAgents = ref(false);
const autoResolveConversationOnTaskEnd = ref(false);
const autoCompleteTaskOnConversationResolve = ref(false);
const isSaving = ref(false);
const isSavingAutomation = ref(false);
const showStepModal = ref(false);
const selectedStep = ref(null);
const isSavingStep = ref(false);
const isDeletingStep = ref(false);
const isInitialized = ref(false);
const isDataLoaded = ref(false);
const showDeleteBoardDialog = ref(false);
const isDeletingBoard = ref(false);

const setActiveBoard = id =>
  store.dispatch('kanban/setActiveBoard', { boardId: id });
const fetchBoards = () => store.dispatch('kanban/fetchBoards');
const updateBoard = data => store.dispatch('kanban/updateBoard', data);
const createStep = data => store.dispatch('kanban/createStep', data);
const updateStep = data => store.dispatch('kanban/updateStep', data);
const removeStep = data => store.dispatch('kanban/deleteStep', data);
const fetchAgents = () => store.dispatch('agents/get');
const fetchInboxes = () => store.dispatch('inboxes/get');
const updateBoardAgents = data =>
  store.dispatch('kanban/updateBoardAgents', data);
const updateBoardInboxes = data =>
  store.dispatch('kanban/updateBoardInboxes', data);
const deleteBoard = id => store.dispatch('kanban/deleteBoard', id);

const saveBoardInfo = async () => {
  isSaving.value = true;
  try {
    await updateBoard({
      id: boardId.value,
      board: {
        name: boardName.value,
        description: boardDescription.value,
      },
    });
    headerBoardName.value = boardName.value;
    useAlert(t('KANBAN.SETTINGS.UPDATE_SUCCESS'));
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('KANBAN.SETTINGS.UPDATE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const saveAgents = async () => {
  try {
    await updateBoardAgents({
      boardId: boardId.value,
      agentIds: selectedAgents.value.map(a => a.id),
    });
    useAlert(t('KANBAN.SETTINGS.UPDATE_SUCCESS'));
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('KANBAN.SETTINGS.UPDATE_ERROR'));
  }
};

const saveInboxes = async () => {
  try {
    await updateBoardInboxes({
      boardId: boardId.value,
      inboxIds: selectedInboxes.value.map(i => i.id),
    });
    useAlert(t('KANBAN.SETTINGS.UPDATE_SUCCESS'));
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('KANBAN.SETTINGS.UPDATE_ERROR'));
  }
};

const saveAutomationSettings = async () => {
  isSavingAutomation.value = true;
  try {
    await updateBoard({
      id: boardId.value,
      board: {
        settings: {
          ...activeBoard.value.settings,
          auto_create_task_for_conversation:
            autoCreateTaskForConversation.value,
          auto_assign_task_to_agent: autoAssignTaskToAgent.value,
          sync_task_and_conversation_agents:
            syncTaskAndConversationAgents.value,
          auto_resolve_conversation_on_task_end:
            autoResolveConversationOnTaskEnd.value,
          auto_complete_task_on_conversation_resolve:
            autoCompleteTaskOnConversationResolve.value,
        },
      },
    });
    useAlert(t('KANBAN.SETTINGS.UPDATE_SUCCESS'));
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('KANBAN.SETTINGS.UPDATE_ERROR'));
  } finally {
    isSavingAutomation.value = false;
  }
};

watch(autoCreateTaskForConversation, async (newValue, oldValue) => {
  if (!isInitialized.value) return;
  if (newValue === oldValue) return;
  await saveAutomationSettings();
});

watch(autoAssignTaskToAgent, async (newValue, oldValue) => {
  if (!isInitialized.value) return;
  if (newValue === oldValue) return;
  await saveAutomationSettings();
});

watch(syncTaskAndConversationAgents, async (newValue, oldValue) => {
  if (!isInitialized.value) return;
  if (newValue === oldValue) return;
  await saveAutomationSettings();
});

watch(autoResolveConversationOnTaskEnd, async (newValue, oldValue) => {
  if (!isInitialized.value) return;
  if (newValue === oldValue) return;
  await saveAutomationSettings();
});

watch(autoCompleteTaskOnConversationResolve, async (newValue, oldValue) => {
  if (!isInitialized.value) return;
  if (newValue === oldValue) return;
  await saveAutomationSettings();
});

watch(selectedAgents, async (newValue, oldValue) => {
  if (!isInitialized.value) return;
  if (
    newValue.length === oldValue.length &&
    newValue.every((item, index) => oldValue[index] === item)
  ) {
    return;
  }
  await saveAgents();
});

watch(selectedInboxes, async (newValue, oldValue) => {
  if (!isInitialized.value) return;
  if (
    newValue.length === oldValue.length &&
    newValue.every((item, index) => oldValue[index] === item)
  ) {
    return;
  }
  await saveInboxes();
});

const initializeBoardData = () => {
  if (activeBoard.value) {
    boardName.value = activeBoard.value.name || '';
    headerBoardName.value = activeBoard.value.name || '';
    boardDescription.value = activeBoard.value.description || '';
    selectedAgents.value = activeBoard.value.assigned_agents || [];
    selectedInboxes.value = activeBoard.value.assigned_inboxes || [];
    autoCreateTaskForConversation.value =
      activeBoard.value.settings?.auto_create_task_for_conversation || false;
    autoAssignTaskToAgent.value =
      activeBoard.value.settings?.auto_assign_task_to_agent || false;
    syncTaskAndConversationAgents.value =
      activeBoard.value.settings?.sync_task_and_conversation_agents || false;
    autoResolveConversationOnTaskEnd.value =
      activeBoard.value.settings?.auto_resolve_conversation_on_task_end ||
      false;
    autoCompleteTaskOnConversationResolve.value =
      activeBoard.value.settings?.auto_complete_task_on_conversation_resolve ||
      false;
    isDataLoaded.value = true;
    nextTick(() => {
      isInitialized.value = true;
    });
  }
};

watch(isDataLoaded, loaded => {
  if (loaded && route.hash) {
    nextTick(() => {
      const element = document.querySelector(route.hash);
      if (element) {
        element.scrollIntoView({ behavior: 'smooth' });
        setTimeout(() => {
          element.classList.add('highlight-section');
          setTimeout(() => {
            element.classList.remove('highlight-section');
          }, 2000);
        }, 500);
      }
    });
  }
});

onMounted(async () => {
  if (!isFazerAiSubscriptionActive.value) {
    router.replace({
      name: 'kanban_list',
      params: { accountId: route.params.accountId },
    });
    return;
  }

  if (!isAdmin.value) {
    router.push({
      name: 'kanban_board_show',
      params: { boardId: boardId.value },
    });
    return;
  }

  await Promise.all([fetchBoards(), fetchAgents(), fetchInboxes()]);

  if (boardId.value) {
    await setActiveBoard(boardId.value);
    initializeBoardData();
  }
});

const getStepTaskCount = stepId => {
  const step = steps.value.find(s => s.id === stepId);
  return step?.tasks_count ?? 0;
};

const updateStepsOrder = async newSteps => {
  const stepIds = newSteps.map(step => step.id);
  const originalBoard = { ...activeBoard.value };

  store.commit('kanban/UPDATE_BOARD', {
    ...activeBoard.value,
    steps_order: stepIds,
  });

  try {
    await updateBoard({
      id: boardId.value,
      board: { steps_order: stepIds },
    });
    useAlert(t('KANBAN.SETTINGS.UPDATE_SUCCESS'));
  } catch (error) {
    store.commit('kanban/UPDATE_BOARD', originalBoard);
    useAlert(parseAPIErrorResponse(error) || t('KANBAN.SETTINGS.UPDATE_ERROR'));
  }
};

const totalTasksCount = computed(() => {
  return activeBoard.value?.total_tasks_count || 0;
});

const stepsCount = computed(() => {
  return steps.value.length;
});

const canStepBeCancelled = index => {
  if (steps.value.length <= 2) return false;
  return index !== 0 && index !== steps.value.length - 1;
};

const getStepStatusBadge = (step, index) => {
  if (steps.value.length <= 1) return null;
  if (step.cancelled) return t('KANBAN.STATUS.CANCELLED');
  if (index === steps.value.length - 1) return t('KANBAN.STATUS.COMPLETED');
  return null;
};

const getStepStatusBadgeClass = (step, index) => {
  if (step.cancelled) return 'bg-n-ruby-3 text-n-ruby-11';
  if (index === steps.value.length - 1) return 'bg-n-teal-3 text-n-teal-11';
  return '';
};

const getStepStatusTooltip = (step, index) => {
  if (step.cancelled) return t('KANBAN.SETTINGS.CANCELLED_STEP_TOOLTIP');
  if (index === steps.value.length - 1)
    return t('KANBAN.SETTINGS.COMPLETED_STEP_TOOLTIP');
  return '';
};

const toggleStepCancelled = async (step, value) => {
  // Optimistically uncancel other steps when setting a new cancelled step
  const previouslyCancelledStep = value
    ? steps.value.find(s => s.cancelled && s.id !== step.id)
    : null;

  if (previouslyCancelledStep) {
    store.commit('kanban/UPDATE_STEP', {
      ...previouslyCancelledStep,
      cancelled: false,
    });
  }

  try {
    await updateStep({
      boardId: boardId.value,
      stepId: step.id,
      step: { cancelled: value },
    });
    useAlert(t('KANBAN.SETTINGS.UPDATE_SUCCESS'));
  } catch (error) {
    // Revert optimistic update on error
    if (previouslyCancelledStep) {
      store.commit('kanban/UPDATE_STEP', {
        ...previouslyCancelledStep,
        cancelled: true,
      });
    }
    useAlert(parseAPIErrorResponse(error) || t('KANBAN.SETTINGS.UPDATE_ERROR'));
  }
};

const openCreateStepModal = () => {
  selectedStep.value = null;
  showStepModal.value = true;
};

const openEditStepModal = step => {
  selectedStep.value = step;
  showStepModal.value = true;
};

const closeStepModal = () => {
  showStepModal.value = false;
  selectedStep.value = null;
};

const saveStep = async data => {
  isSavingStep.value = true;
  try {
    if (data.id) {
      await updateStep({
        boardId: boardId.value,
        stepId: data.id,
        step: data,
      });
    } else {
      await createStep({
        boardId: boardId.value,
        step: data,
      });
    }
    closeStepModal();
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('KANBAN.SETTINGS.UPDATE_ERROR'));
  } finally {
    isSavingStep.value = false;
  }
};

const deleteStep = async id => {
  isDeletingStep.value = true;
  try {
    await removeStep({
      boardId: boardId.value,
      stepId: id,
    });
    closeStepModal();
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('KANBAN.SETTINGS.UPDATE_ERROR'));
  } finally {
    isDeletingStep.value = false;
  }
};

const isStepDeletable = computed(() => {
  if (!selectedStep.value) return true;
  return steps.value.length > 1;
});

const copyId = async () => {
  await copyTextToClipboard(boardId.value);
  useAlert(t('COMPONENTS.CODE.COPY_SUCCESSFUL'));
};

const openDeleteBoardDialog = () => {
  showDeleteBoardDialog.value = true;
};

const closeDeleteBoardDialog = () => {
  showDeleteBoardDialog.value = false;
};

const confirmDeleteBoard = async () => {
  if (isDeletingBoard.value) return;

  isDeletingBoard.value = true;
  try {
    await deleteBoard(boardId.value);
    router.push({
      name: 'kanban_list',
      params: { accountId: route.params.accountId },
    });
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('KANBAN.SETTINGS.DELETE_ERROR'));
  } finally {
    isDeletingBoard.value = false;
    closeDeleteBoardDialog();
  }
};
</script>

<template>
  <div
    class="flex h-full w-full flex-col overflow-hidden bg-n-background font-inter"
  >
    <div
      class="w-full flex justify-center px-6 sm:py-8 lg:px-16 pt-6 sm:pt-8 pb-4"
    >
      <div class="w-full max-w-7xl">
        <SettingsLayout :is-loading="false">
          <template #header>
            <div class="flex items-center gap-4 w-full min-w-0">
              <router-link
                :to="{
                  name: 'kanban_board_show',
                  params: {
                    accountId: route.params.accountId,
                    boardId: boardId,
                  },
                }"
                class="flex items-center"
              >
                <Button
                  icon="i-lucide-arrow-left"
                  variant="ghost"
                  color="slate"
                  size="sm"
                />
              </router-link>
              <div
                v-if="!isDataLoaded"
                class="h-7 w-48 bg-n-slate-3 rounded animate-pulse"
              />
              <h1
                v-else
                class="text-xl font-medium tracking-tight text-n-slate-12 truncate"
              >
                {{ headerBoardName }}
              </h1>
              <div
                v-if="!isDataLoaded"
                class="h-5 w-8 bg-n-slate-3 rounded-full animate-pulse flex-shrink-0"
              />
              <span
                v-else
                class="flex h-5 min-w-[1.25rem] items-center justify-center rounded-full bg-n-slate-5 px-2 text-xs font-medium text-n-slate-12 flex-shrink-0"
              >
                {{ totalTasksCount }}
              </span>
              <div class="flex items-center gap-2 ml-auto flex-shrink-0">
                <span
                  class="text-xs font-medium text-n-slate-11 whitespace-nowrap"
                >
                  {{ t('KANBAN.MODAL.ID_LABEL') }} {{ boardId }}
                </span>
                <Button
                  variant="ghost"
                  color="slate"
                  size="xs"
                  icon="i-lucide-copy"
                  @click="copyId"
                />
              </div>
            </div>
          </template>
        </SettingsLayout>
      </div>
    </div>
    <div
      v-if="!isDataLoaded"
      class="flex-1 overflow-y-auto px-6 lg:px-16 scrollbar-custom flex justify-center"
    >
      <div class="w-full max-w-7xl animate-pulse">
        <div class="flex flex-col gap-4 pb-6">
          <section class="flex flex-col gap-4">
            <div class="flex items-center justify-between">
              <div class="h-6 w-32 bg-n-slate-3 rounded" />
              <div class="h-8 w-20 bg-n-slate-3 rounded-md" />
            </div>
            <div class="flex flex-col gap-4">
              <div class="flex flex-col gap-2">
                <div class="h-4 w-24 bg-n-slate-3 rounded" />
                <div class="h-10 w-full bg-n-slate-3 rounded-md" />
              </div>
              <div class="flex flex-col gap-2">
                <div class="h-4 w-32 bg-n-slate-3 rounded" />
                <div class="h-40 w-full bg-n-slate-3 rounded-md" />
              </div>
            </div>
          </section>

          <section class="flex flex-col gap-4">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-2">
                <div class="h-6 w-24 bg-n-slate-3 rounded" />
                <div class="h-5 w-8 bg-n-slate-3 rounded-full" />
              </div>
              <div class="h-8 w-28 bg-n-slate-3 rounded-md" />
            </div>
            <div class="flex flex-col gap-2">
              <div
                v-for="i in 3"
                :key="i"
                class="h-12 w-full bg-n-slate-3 rounded-lg"
              />
            </div>
          </section>

          <section class="flex flex-col gap-4">
            <div class="h-6 w-24 bg-n-slate-3 rounded" />
            <div class="h-10 w-full bg-n-slate-3 rounded-md" />
          </section>

          <section class="flex flex-col gap-4">
            <div class="h-6 w-24 bg-n-slate-3 rounded" />
            <div class="h-10 w-full bg-n-slate-3 rounded-md" />
          </section>
        </div>
      </div>
    </div>
    <div
      v-else
      class="flex-1 overflow-y-auto px-6 lg:px-16 scrollbar-custom flex justify-center"
    >
      <div class="w-full max-w-7xl">
        <div class="flex flex-col gap-4 pb-6">
          <section class="flex flex-col gap-4">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-medium text-n-slate-12">
                {{ t('KANBAN.SETTINGS.BASIC_INFO') }}
              </h2>
              <Button
                :disabled="isSaving"
                :loading="isSaving"
                size="sm"
                @click="saveBoardInfo"
              >
                {{ t('KANBAN.SETTINGS.SAVE') }}
              </Button>
            </div>
            <div class="flex flex-col gap-4">
              <Input
                v-model="boardName"
                :label="t('KANBAN.SETTINGS.NAME_LABEL')"
                :placeholder="t('KANBAN.SETTINGS.NAME_PLACEHOLDER')"
                autocomplete="off"
                data-lpignore="true"
                data-1p-ignore="true"
                maxlength="60"
              />
              <Editor
                id="board-description"
                v-model="boardDescription"
                :label="t('KANBAN.SETTINGS.DESCRIPTION_LABEL')"
                :placeholder="t('KANBAN.SETTINGS.DESCRIPTION_PLACEHOLDER')"
                :max-length="2000"
                enable-line-breaks
                class="[&_.ProseMirror-woot-style]:!min-h-[120px] [&_.ProseMirror-woot-style]:!max-h-[450px] [&_.ProseMirror-woot-style]:!resize-y [&_.ProseMirror-woot-style]:!overflow-y-auto"
              />
            </div>
          </section>

          <section class="flex flex-col gap-4">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-2">
                <h2 class="text-lg font-medium text-n-slate-12">
                  {{ t('KANBAN.SETTINGS.STEPS') }}
                </h2>
                <span
                  class="flex h-5 min-w-[1.25rem] items-center justify-center rounded-full bg-n-slate-5 px-2 text-xs font-medium text-n-slate-12"
                >
                  {{ stepsCount }}
                </span>
              </div>
              <Button
                icon="i-lucide-plus"
                size="sm"
                variant="outline"
                color="slate"
                @click="openCreateStepModal"
              >
                {{ t('KANBAN.SETTINGS.ADD_STEP') }}
              </Button>
            </div>
            <Draggable
              :model-value="steps"
              animation="200"
              ghost-class="ghost"
              item-key="id"
              handle=".drag-handle"
              class="flex flex-col gap-2"
              @update:model-value="updateStepsOrder"
            >
              <template #item="{ element: step, index }">
                <div
                  class="flex items-center gap-3 p-2 border rounded-lg border-n-slate-3 bg-n-alpha-1 hover:bg-n-alpha-2 transition-colors"
                >
                  <button
                    class="drag-handle cursor-grab active:cursor-grabbing text-n-slate-9 hover:text-n-slate-11"
                  >
                    <i class="i-lucide-grip-vertical w-5 h-5" />
                  </button>
                  <div
                    class="w-3 h-3 rounded-full flex-shrink-0"
                    :style="{ backgroundColor: step.color }"
                  />
                  <div class="flex items-center gap-2 flex-1 min-w-0">
                    <span class="text-sm font-medium text-n-slate-12 truncate">
                      {{ step.name }}
                    </span>
                    <span
                      class="flex h-5 min-w-[1.25rem] items-center justify-center rounded-full bg-n-slate-5 px-2 text-xs font-medium text-n-slate-12 flex-shrink-0"
                    >
                      {{ getStepTaskCount(step.id) }}
                    </span>
                    <span
                      v-if="getStepStatusBadge(step, index)"
                      v-tooltip="getStepStatusTooltip(step, index)"
                      class="flex h-5 items-center justify-center rounded-full px-2 text-xs font-medium flex-shrink-0 cursor-help"
                      :class="getStepStatusBadgeClass(step, index)"
                    >
                      {{ getStepStatusBadge(step, index) }}
                    </span>
                  </div>
                  <div
                    v-if="canStepBeCancelled(index)"
                    v-tooltip="t('KANBAN.SETTINGS.CANCELLED_STEP_TOOLTIP')"
                    class="flex items-center gap-2"
                  >
                    <span class="text-xs text-n-slate-11">
                      {{ t('KANBAN.SETTINGS.CANCELLED_LABEL') }}
                    </span>
                    <Switch
                      :model-value="step.cancelled"
                      size="sm"
                      @update:model-value="toggleStepCancelled(step, $event)"
                    />
                  </div>
                  <Button
                    icon="i-lucide-pencil"
                    variant="ghost"
                    color="slate"
                    size="xs"
                    @click="openEditStepModal(step)"
                  />
                </div>
              </template>
            </Draggable>
          </section>

          <section id="board-agents" class="flex flex-col gap-4">
            <h2 class="text-lg font-medium text-n-slate-12">
              {{ t('KANBAN.SETTINGS.AGENTS') }}
            </h2>
            <multiselect
              v-model="selectedAgents"
              :options="agentOptions"
              track-by="id"
              label="name"
              multiple
              :close-on-select="false"
              :clear-on-select="false"
              :placeholder="t('KANBAN.SETTINGS.AGENTS_PLACEHOLDER')"
              :select-label="t('FORMS.MULTISELECT.ENTER_TO_SELECT')"
              :deselect-label="t('FORMS.MULTISELECT.ENTER_TO_REMOVE')"
              :selected-label="t('FORMS.MULTISELECT.SELECTED')"
              class="!mb-0"
            >
              <template #tag="{ option, remove }">
                <span
                  class="multiselect__tag !inline-flex items-center gap-2 !relative !pl-7"
                >
                  <Avatar
                    :src="option.avatar_url"
                    :name="option.name"
                    :size="16"
                    :status="option.availability_status"
                    class="!absolute !left-1.5 !top-1/2 !-translate-y-1/2"
                  />
                  <span
                    class="multiselect__tag-text !inline-block !max-w-[150px] !truncate"
                  >
                    {{ option.name }}
                  </span>
                  <i
                    class="multiselect__tag-icon"
                    @mousedown.prevent
                    @click.prevent.stop="remove(option)"
                    @keypress.enter.prevent="remove(option)"
                  />
                </span>
              </template>
              <template #option="{ option }">
                <div class="flex items-center gap-2 min-w-0">
                  <Avatar
                    :src="option.avatar_url"
                    :name="option.name"
                    :size="16"
                    :status="option.availability_status"
                    class="leading-none text-center"
                  />
                  <span class="truncate">{{ option.name }}</span>
                </div>
              </template>
              <template #noResult>
                {{ t('KANBAN.SETTINGS.NO_AGENTS_FOUND') }}
              </template>
              <template #noOptions>
                {{ t('KANBAN.SETTINGS.NO_AGENTS_AVAILABLE') }}
              </template>
            </multiselect>
          </section>

          <section id="board-inboxes" class="flex flex-col gap-4">
            <h2 class="text-lg font-medium text-n-slate-12">
              {{ t('KANBAN.SETTINGS.INBOXES') }}
            </h2>
            <multiselect
              v-model="selectedInboxes"
              :options="inboxes"
              track-by="id"
              label="name"
              multiple
              :close-on-select="false"
              :clear-on-select="false"
              :placeholder="t('KANBAN.SETTINGS.INBOXES_PLACEHOLDER')"
              :select-label="t('FORMS.MULTISELECT.ENTER_TO_SELECT')"
              :deselect-label="t('FORMS.MULTISELECT.ENTER_TO_REMOVE')"
              :selected-label="t('FORMS.MULTISELECT.SELECTED')"
              class="!mb-0"
            >
              <template #tag="{ option, remove }">
                <span
                  class="multiselect__tag !inline-flex items-center gap-2 !relative !pl-7"
                >
                  <div class="!absolute !left-1.5 !top-1/2 !-translate-y-1/2">
                    <ChannelIcon class="size-4" :inbox="option" />
                  </div>
                  <span
                    class="multiselect__tag-text !inline-block !max-w-[150px] !truncate"
                  >
                    {{ option.name }}
                  </span>
                  <i
                    class="multiselect__tag-icon"
                    @mousedown.prevent
                    @click.prevent.stop="remove(option)"
                    @keypress.enter.prevent="remove(option)"
                  />
                </span>
              </template>
              <template #option="{ option }">
                <div class="flex items-center gap-2 min-w-0">
                  <ChannelIcon
                    class="size-4 flex-shrink-0 min-w-4"
                    :inbox="option"
                  />
                  <span class="truncate">{{ option.name }}</span>
                </div>
              </template>
              <template #noResult>
                {{ t('KANBAN.SETTINGS.NO_INBOXES_FOUND') }}
              </template>
              <template #noOptions>
                {{ t('KANBAN.SETTINGS.NO_INBOXES_AVAILABLE') }}
              </template>
            </multiselect>
          </section>

          <section id="board-automation" class="flex flex-col gap-4">
            <div class="flex flex-col gap-1">
              <h2 class="text-lg font-medium text-n-slate-12">
                {{ t('KANBAN.AUTOMATION.TITLE') }}
              </h2>
              <p class="text-sm text-n-slate-11">
                {{ t('KANBAN.AUTOMATION.SUBHEADER') }}
                <router-link
                  :to="{
                    name: 'automation_list',
                    params: { accountId: route.params.accountId },
                  }"
                  class="text-n-brand underline hover:no-underline"
                >
                  {{ t('KANBAN.AUTOMATION.SUBHEADER_LINK') }}
                </router-link>
              </p>
            </div>
            <label class="flex items-start gap-3">
              <Switch v-model="autoCreateTaskForConversation" />
              <div class="flex flex-col gap-1">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('KANBAN.AUTOMATION.AUTO_CREATE_TASK') }}
                </span>
                <span class="text-sm text-n-slate-11">
                  {{ t('KANBAN.AUTOMATION.AUTO_CREATE_TASK_DESCRIPTION') }}
                </span>
              </div>
            </label>
            <label class="flex items-start gap-3">
              <Switch v-model="autoAssignTaskToAgent" />
              <div class="flex flex-col gap-1">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('KANBAN.AUTOMATION.AUTO_ASSIGN_TASK') }}
                </span>
                <span class="text-sm text-n-slate-11">
                  {{ t('KANBAN.AUTOMATION.AUTO_ASSIGN_TASK_DESCRIPTION') }}
                </span>
              </div>
            </label>
            <label class="flex items-start gap-3">
              <Switch v-model="syncTaskAndConversationAgents" />
              <div class="flex flex-col gap-1">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('KANBAN.AUTOMATION.SYNC_TASK_CONVERSATION_AGENTS') }}
                </span>
                <span class="text-sm text-n-slate-11">
                  {{
                    t(
                      'KANBAN.AUTOMATION.SYNC_TASK_CONVERSATION_AGENTS_DESCRIPTION'
                    )
                  }}
                </span>
              </div>
            </label>
            <label class="flex items-start gap-3">
              <Switch v-model="autoResolveConversationOnTaskEnd" />
              <div class="flex flex-col gap-1">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('KANBAN.AUTOMATION.AUTO_RESOLVE_CONVERSATION') }}
                </span>
                <span class="text-sm text-n-slate-11">
                  {{
                    t('KANBAN.AUTOMATION.AUTO_RESOLVE_CONVERSATION_DESCRIPTION')
                  }}
                </span>
              </div>
            </label>
            <label class="flex items-start gap-3">
              <Switch v-model="autoCompleteTaskOnConversationResolve" />
              <div class="flex flex-col gap-1">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('KANBAN.AUTOMATION.AUTO_COMPLETE_TASK') }}
                </span>
                <span class="text-sm text-n-slate-11">
                  {{ t('KANBAN.AUTOMATION.AUTO_COMPLETE_TASK_DESCRIPTION') }}
                </span>
              </div>
            </label>
          </section>

          <section class="flex flex-col gap-4 pt-4 border-t border-n-slate-6">
            <div class="flex flex-col gap-2">
              <h2 class="text-lg font-medium text-n-ruby-11">
                {{ t('KANBAN.SETTINGS.DELETE_BOARD') }}
              </h2>
              <p class="text-sm text-n-slate-11">
                {{ t('KANBAN.SETTINGS.DELETE_BOARD_WARNING') }}
              </p>
            </div>
            <div>
              <Button
                variant="outline"
                color="ruby"
                size="sm"
                icon="i-lucide-trash-2"
                @click="openDeleteBoardDialog"
              >
                {{ t('KANBAN.SETTINGS.DELETE_BOARD') }}
              </Button>
            </div>
          </section>
        </div>
      </div>
    </div>
    <KanbanStepModal
      v-if="showStepModal"
      :show="showStepModal"
      :step="selectedStep"
      :board-name="boardName"
      :is-saving="isSavingStep"
      :is-deleting="isDeletingStep"
      :can-delete="isStepDeletable"
      @close="closeStepModal"
      @save="saveStep"
      @delete="deleteStep"
    />
    <woot-confirm-delete-modal
      v-if="showDeleteBoardDialog"
      v-model:show="showDeleteBoardDialog"
      :title="t('KANBAN.SETTINGS.DELETE_BOARD_CONFIRM_TITLE')"
      :message="
        t('KANBAN.SETTINGS.DELETE_BOARD_CONFIRM_MESSAGE', { name: boardName })
      "
      :confirm-text="
        t('KANBAN.SETTINGS.DELETE_BOARD_CONFIRM_YES', { name: boardName })
      "
      :reject-text="
        t('KANBAN.SETTINGS.DELETE_BOARD_CONFIRM_NO', { name: boardName })
      "
      :confirm-value="boardName"
      :confirm-place-holder-text="
        t('KANBAN.SETTINGS.DELETE_BOARD_PLACEHOLDER', { name: boardName })
      "
      :is-loading="isDeletingBoard"
      @on-confirm="confirmDeleteBoard"
      @on-close="closeDeleteBoardDialog"
    />
  </div>
</template>

<style scoped>
:deep(main) {
  @apply flex-1 flex flex-col min-h-0;
}

@keyframes highlight {
  0% {
    background-color: transparent;
  }
  20% {
    @apply bg-n-slate-3 dark:bg-n-alpha-2;
  }
  50% {
    @apply bg-n-slate-3 dark:bg-n-alpha-2;
  }
  100% {
    background-color: transparent;
  }
}

.highlight-section {
  animation: highlight 2s ease-out;
  @apply rounded-lg -m-2 p-2;
}
</style>
