<script setup>
import { ref, computed, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { shortTimestampFromDate } from 'shared/helpers/timeHelper';
import kanbanModule from 'kanban/store/modules/kanban';
import TasksAPI from 'kanban/api/tasks';
import MultiselectDropdown from 'shared/components/ui/MultiselectDropdown.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import LabelItem from 'dashboard/components-next/label/LabelItem.vue';
import AddLabel from 'dashboard/components-next/label/AddLabel.vue';
import KanbanContextDropdown from './KanbanContextDropdown.vue';
import KanbanTaskDatePicker from './KanbanTaskDatePicker.vue';
import ContactDetailsItem from 'dashboard/routes/dashboard/conversation/ContactDetailsItem.vue';
import BasePaywallModal from 'dashboard/routes/dashboard/settings/components/BasePaywallModal.vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import { useKanban } from '../composables/useKanban';
import types from 'dashboard/store/mutation-types';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const props = defineProps({
  conversationId: {
    type: Number,
    required: true,
  },
  contactName: {
    type: String,
    default: '',
  },
  kanbanTask: {
    type: Object,
    default: null,
  },
  inboxId: {
    type: Number,
    default: null,
  },
});

const store = useStore();
const { t } = useI18n();
const router = useRouter();
const { priorities } = useKanban();
const { isCloudFeatureEnabled, accountId, isOnChatwootCloud } = useAccount();

const currentUser = useMapGetter('getCurrentUser');
const accountLabels = useMapGetter('labels/getLabels');

const fazerAiSubscription = computed(
  () => store.getters['globalConfig/getFazerAiSubscription']
);
const isFazerAiSubscriptionActive = computed(() => {
  const status = fazerAiSubscription.value?.status;
  return ['active', 'past_due', 'trialing'].includes(status);
});

const isKanbanEnabled = computed(
  () =>
    isCloudFeatureEnabled(FEATURE_FLAGS.KANBAN) &&
    isFazerAiSubscriptionActive.value
);
const isSuperAdmin = computed(() => currentUser.value?.type === 'SuperAdmin');
const paywallI18nKey = computed(() =>
  isOnChatwootCloud.value ? 'PAYWALL' : 'ENTERPRISE_PAYWALL'
);

const openBilling = () => {
  router.push({
    name: 'billing_settings_index',
    params: { accountId: accountId.value },
  });
};

if (!store.hasModule('kanban')) {
  store.registerModule('kanban', kanbanModule);
}

const selectedBoard = ref(null);
const existingTask = ref(null);
const isCreating = ref(false);
const isUpdating = ref(false);
const steps = ref([]);
const boardAgents = ref([]);
const selectedLabels = ref([]);
const startDate = ref(null);
const dueDate = ref(null);

const boards = computed(() => store.state.kanban.boards);
const preferences = computed(() => store.state.kanban.preferences);

const boardOptions = computed(() => {
  const favoriteBoardIds = preferences.value?.favorite_board_ids || [];

  const filteredBoards = boards.value.filter(f => {
    const hasSteps = f.steps_summary && f.steps_summary.length > 0;
    if (!hasSteps) {
      return false;
    }

    if (!props.inboxId) return true;
    const inboxIds = f.assigned_inbox_ids || [];
    return inboxIds.includes(props.inboxId);
  });

  const mappedBoards = filteredBoards.map(f => ({
    id: f.id,
    name: f.name,
    isFavorite: favoriteBoardIds.includes(f.id),
    icon: favoriteBoardIds.includes(f.id) ? 'i-ri-star-fill' : null,
    color: favoriteBoardIds.includes(f.id) ? '#eab308' : null, // yellow-500
  }));

  return mappedBoards.sort((a, b) => {
    if (a.isFavorite && !b.isFavorite) return -1;
    if (!a.isFavorite && b.isFavorite) return 1;
    return a.name.localeCompare(b.name);
  });
});
const timeAgo = computed(() => {
  if (!existingTask.value) return '';
  const date =
    existingTask.value.step_changed_at || existingTask.value.created_at;
  if (!date) return '';
  const unixTime = new Date(date).getTime() / 1000;
  return shortTimestampFromDate({ time: unixTime, withAgo: false, t });
});

const stepChangedDate = computed(() => {
  if (!existingTask.value) return '';
  const date =
    existingTask.value.step_changed_at || existingTask.value.created_at;
  if (!date) return '';
  const formattedDate = new Date(date).toLocaleString();

  if (existingTask.value.status === 'completed') {
    return t('KANBAN.WON_AT_TOOLTIP', { date: formattedDate });
  }
  if (existingTask.value.status === 'cancelled') {
    return t('KANBAN.LOST_AT_TOOLTIP', { date: formattedDate });
  }
  if (existingTask.value.step_changed_at) {
    return t('KANBAN.STEP_CHANGED_AT_TOOLTIP', { date: formattedDate });
  }
  return t('KANBAN.CREATED_AT_TOOLTIP', { date: formattedDate });
});

const statusIcon = computed(() => {
  if (!existingTask.value) return null;
  if (existingTask.value.status === 'completed')
    return 'i-lucide-check-circle-2';
  if (existingTask.value.status === 'cancelled') return 'i-lucide-x-circle';
  return null;
});

const statusColor = computed(() => {
  if (!existingTask.value) return '';
  if (existingTask.value.status === 'completed') return 'text-n-teal-11';
  if (existingTask.value.status === 'cancelled') return 'text-n-ruby-11';
  return '';
});

const statusTooltip = computed(() => {
  if (!existingTask.value) return '';
  if (existingTask.value.status === 'completed')
    return t('KANBAN.STATUS.COMPLETED');
  if (existingTask.value.status === 'cancelled')
    return t('KANBAN.STATUS.CANCELLED');
  return '';
});

const currentStep = computed(() => {
  if (!existingTask.value) return null;
  return steps.value.find(s => s.id === existingTask.value.board_step_id);
});

const currentPriority = computed(() => {
  if (!existingTask.value) return null;
  return (
    priorities.value.find(p => p.id === existingTask.value.priority) ||
    priorities.value.find(p => p.id === null)
  );
});

const nextStep = computed(() => {
  if (!currentStep.value) return null;
  const currentIndex = steps.value.findIndex(
    s => s.id === currentStep.value.id
  );
  if (currentIndex === -1 || currentIndex === steps.value.length - 1)
    return null;
  return steps.value[currentIndex + 1];
});

const lastStep = computed(() => {
  if (steps.value.length === 0) return null;
  return steps.value[steps.value.length - 1];
});

const canComplete = computed(() => {
  if (!lastStep.value || !existingTask.value) return false;
  return existingTask.value.board_step_id !== lastStep.value.id;
});

const selectedAgentIds = computed(() => {
  return (existingTask.value?.assigned_agents || []).map(a => a.id);
});

const agentOptions = computed(() => {
  return boardAgents.value.map(agent => ({
    value: agent.id,
    label: agent.name,
  }));
});

const labelMenuItems = computed(() =>
  accountLabels.value.map(label => ({
    label: label.title,
    value: label.id,
    thumbnail: { name: label.title, color: label.color },
    isSelected: selectedLabels.value.some(l => l.title === label.title),
    action: 'label',
  }))
);

const taskUrl = computed(() => {
  if (!existingTask.value) return null;
  return `/app/accounts/${accountId.value}/kanban/${existingTask.value.board_id}/task/${existingTask.value.id}`;
});

const boardName = computed(() => {
  if (!existingTask.value) return '';
  const board = boards.value.find(f => f.id === existingTask.value.board_id);
  return board?.name || '';
});

const showSelfAssign = computed(() => {
  if (!existingTask.value || !currentUser.value) return false;
  const isAssignedToSelf = selectedAgentIds.value.includes(
    currentUser.value.id
  );
  const isInAgentsList = boardAgents.value.some(
    a => a.id === currentUser.value.id
  );
  return !isAssignedToSelf && isInAgentsList;
});

const parseDate = dateStr => {
  if (!dateStr) return null;
  const date = new Date(dateStr);
  return Number.isNaN(date.getTime()) ? null : date;
};

const normalizeDate = date => {
  if (!date) return null;
  return new Date(date).toISOString();
};

watch(
  () => props.kanbanTask,
  newTask => {
    existingTask.value = newTask;
    if (newTask?.board) {
      steps.value = newTask.board.steps || [];
      boardAgents.value = newTask.board.assigned_agents || [];
    } else {
      steps.value = [];
      boardAgents.value = [];
      selectedBoard.value = null;
    }
    if (!isUpdating.value && accountLabels.value.length > 0) {
      const taskLabelTitles = newTask?.labels || [];
      selectedLabels.value = accountLabels.value
        .filter(label => taskLabelTitles.includes(label.title))
        .sort((a, b) => a.title.localeCompare(b.title));
    }
    if (!isUpdating.value) {
      startDate.value = parseDate(newTask?.start_date);
      dueDate.value = parseDate(newTask?.due_date);
    }
  },
  { immediate: true }
);

watch(
  () => accountLabels.value,
  newLabels => {
    if (
      !isUpdating.value &&
      newLabels.length > 0 &&
      existingTask.value?.labels?.length > 0 &&
      selectedLabels.value.length === 0
    ) {
      const taskLabelTitles = existingTask.value.labels || [];
      selectedLabels.value = newLabels
        .filter(label => taskLabelTitles.includes(label.title))
        .sort((a, b) => a.title.localeCompare(b.title));
    }
  }
);

const createTask = async () => {
  if (!selectedBoard.value) return;

  isCreating.value = true;
  try {
    const baseTitle = t('KANBAN.CONVERSATION_TASK_TITLE', {
      id: props.conversationId,
    });
    const titleWithContact = props.contactName
      ? `${baseTitle} - ${props.contactName}`
      : baseTitle;
    const title = titleWithContact.slice(0, 255);

    const taskData = {
      task: {
        title,
        board_id: selectedBoard.value.id,
        conversation_ids: [props.conversationId],
      },
    };

    const response = await TasksAPI.create(taskData);
    existingTask.value = response.data;
    store.commit(types.UPDATE_CONVERSATION_KANBAN_TASK, {
      conversationId: props.conversationId,
      task: response.data,
    });
    selectedBoard.value = null;
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('KANBAN.ERROR'));
  } finally {
    isCreating.value = false;
  }
};

const updateTask = async updates => {
  if (!existingTask.value || isUpdating.value) return;

  const originalTask = { ...existingTask.value };
  const originalLabels = [...selectedLabels.value];

  existingTask.value = { ...existingTask.value, ...updates };
  store.commit(types.UPDATE_CONVERSATION_KANBAN_TASK, {
    conversationId: props.conversationId,
    task: existingTask.value,
  });

  isUpdating.value = true;
  try {
    const response = await TasksAPI.update(originalTask.id, updates);
    existingTask.value = response.data;
    store.commit(types.UPDATE_CONVERSATION_KANBAN_TASK, {
      conversationId: props.conversationId,
      task: response.data,
    });
    const responseLabelTitles = response.data.labels || [];
    selectedLabels.value = accountLabels.value
      .filter(label => responseLabelTitles.includes(label.title))
      .sort((a, b) => a.title.localeCompare(b.title));
  } catch (error) {
    existingTask.value = originalTask;
    selectedLabels.value = originalLabels;
    store.commit(types.UPDATE_CONVERSATION_KANBAN_TASK, {
      conversationId: props.conversationId,
      task: originalTask,
    });
    useAlert(parseAPIErrorResponse(error) || t('KANBAN.ERROR'));
  } finally {
    isUpdating.value = false;
  }
};

const handleStepChange = step => {
  updateTask({ board_step_id: step.id });
};

const handlePriorityChange = priority => {
  updateTask({ priority: priority.id });
};

const handleAgentsChange = agentIds => {
  const agentObjects = boardAgents.value
    .filter(a => agentIds.includes(a.id))
    .map(a => ({
      id: a.id,
      name: a.name,
      avatar_url: a.avatar_url,
      availability_status: a.availability_status,
    }));
  updateTask({
    assigned_agent_ids: agentIds,
    assigned_agents: agentObjects,
  });
};

const hoveredLabel = ref(null);

const handleLabelsChange = ({ value: labelId }) => {
  const label = accountLabels.value.find(l => l.id === labelId);
  if (!label) return;

  const isAlreadySelected = selectedLabels.value.some(
    l => l.title === label.title
  );
  if (isAlreadySelected) {
    selectedLabels.value = selectedLabels.value.filter(
      l => l.title !== label.title
    );
  } else {
    selectedLabels.value = [...selectedLabels.value, label].sort((a, b) =>
      a.title.localeCompare(b.title)
    );
  }
  updateTask({ labels: selectedLabels.value.map(l => l.title) });
};

const handleRemoveLabel = label => {
  selectedLabels.value = selectedLabels.value.filter(
    l => l.title !== label.title
  );
  updateTask({ labels: selectedLabels.value.map(l => l.title) });
};

const moveToNextStep = () => {
  if (nextStep.value) {
    updateTask({ board_step_id: nextStep.value.id });
  }
};

const markComplete = () => {
  if (lastStep.value) {
    updateTask({ board_step_id: lastStep.value.id });
  }
};

const assignToMe = () => {
  if (!currentUser.value) return;
  const currentIds = (existingTask.value?.assigned_agents || []).map(a => a.id);
  if (currentIds.includes(currentUser.value.id)) return;
  handleAgentsChange([...currentIds, currentUser.value.id]);
};

const handleStartDateChange = date => {
  startDate.value = date;
  updateTask({ start_date: normalizeDate(date) });
};

const handleDueDateChange = date => {
  dueDate.value = date;
  updateTask({ due_date: normalizeDate(date) });
};
</script>

<template>
  <div class="kanban-conversation-panel flex flex-col p-4">
    <!-- Paywall State -->
    <template v-if="!isKanbanEnabled">
      <BasePaywallModal
        feature-prefix="KANBAN"
        :i18n-key="paywallI18nKey"
        :is-super-admin="isSuperAdmin"
        :is-on-chatwoot-cloud="isOnChatwootCloud"
        class="!max-w-none !shadow-none !border-0 !px-0 !py-0"
        @upgrade="openBilling"
      />
    </template>

    <!-- Normal Content (when feature is enabled) -->
    <template v-else>
      <!-- No Task State -->
      <div v-if="!existingTask && !isCreating" class="multiselect-wrap--small">
        <ContactDetailsItem compact :title="$t('KANBAN.ADD_TO_BOARD')" />
        <MultiselectDropdown
          :selected-item="selectedBoard"
          :options="boardOptions"
          :multiselector-placeholder="$t('KANBAN.SELECT_BOARD')"
          :input-placeholder="$t('KANBAN.SEARCH_BOARDS')"
          @select="
            val => {
              selectedBoard = val;
              createTask();
            }
          "
        />
      </div>

      <!-- Creating Task State -->
      <div v-else-if="isCreating" class="flex flex-col gap-3">
        <!-- Board Badge -->
        <div class="flex flex-col gap-2">
          <div
            class="inline-flex items-center gap-1.5 text-xs px-2 py-1 rounded-md bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-300 self-start max-w-full"
          >
            <span class="i-lucide-kanban size-3 shrink-0" />
            <span class="font-medium truncate">{{ selectedBoard?.name }}</span>
          </div>
          <div
            class="h-5 rounded bg-slate-100 dark:bg-slate-800 animate-pulse w-3/4"
          />
        </div>

        <!-- Step Skeleton -->
        <div class="multiselect-wrap--small">
          <ContactDetailsItem compact :title="$t('KANBAN.MODAL.STEP_LABEL')" />
          <div
            class="h-9 rounded-lg bg-slate-100 dark:bg-slate-800 animate-pulse"
          />
        </div>

        <!-- Priority Skeleton -->
        <div class="multiselect-wrap--small">
          <div class="flex items-center justify-between mb-1.5">
            <span class="text-sm font-medium text-n-slate-12">
              {{ $t('KANBAN.MODAL.PRIORITY_LABEL') }}
            </span>
          </div>
          <div
            class="h-9 rounded-lg bg-slate-100 dark:bg-slate-800 animate-pulse"
          />
        </div>

        <!-- Agents Skeleton -->
        <div class="multiselect-wrap--small">
          <ContactDetailsItem compact :title="$t('KANBAN.ASSIGNED_AGENTS')" />
          <div
            class="h-9 rounded-lg bg-slate-100 dark:bg-slate-800 animate-pulse"
          />
        </div>
      </div>

      <!-- Task Exists State -->
      <div v-else class="flex flex-col gap-3">
        <!-- Board Badge & Task Title -->
        <div class="flex flex-col gap-2">
          <div
            class="inline-flex items-center gap-1.5 text-xs px-2 py-1 rounded-md bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-300 self-start max-w-full"
          >
            <span class="i-lucide-kanban size-3 shrink-0" />
            <span class="font-medium truncate">{{ boardName }}</span>
          </div>
          <div class="flex items-center gap-2 min-w-0">
            <span
              v-if="statusIcon"
              v-tooltip="statusTooltip"
              :class="[statusIcon, statusColor]"
              class="size-4 flex-shrink-0"
            />
            <router-link
              :to="taskUrl"
              class="text-sm font-medium text-woot-500 hover:underline text-left truncate flex-1 min-w-0"
            >
              {{ existingTask.title }}
            </router-link>
          </div>
        </div>

        <!-- Step -->
        <div class="multiselect-wrap--small">
          <ContactDetailsItem compact :title="$t('KANBAN.MODAL.STEP_LABEL')" />
          <div class="flex items-center gap-1">
            <div class="flex-1 min-w-0">
              <KanbanContextDropdown
                :options="steps"
                :selected-item="currentStep"
                hide-search
                :has-thumbnail="false"
                @select="handleStepChange"
              >
                <template #trigger="{ open }">
                  <button
                    class="w-full flex items-center gap-2 px-3 py-2 text-sm text-left rounded-lg outline outline-1 outline-n-strong hover:bg-slate-50 dark:hover:bg-slate-800 min-w-0"
                    @click.stop="open"
                  >
                    <div
                      class="size-2 rounded-full flex-shrink-0"
                      :style="{ backgroundColor: currentStep?.color }"
                    />
                    <span class="truncate text-slate-900 dark:text-slate-100">
                      {{
                        currentStep?.name || $t('KANBAN.MODAL.STEP_PLACEHOLDER')
                      }}
                    </span>
                  </button>
                </template>
              </KanbanContextDropdown>
            </div>
            <Button
              v-if="nextStep"
              v-tooltip="
                $t('KANBAN.MOVE_TO_NEXT_STEP', { step: nextStep.name })
              "
              variant="ghost"
              size="sm"
              class="shrink-0 !px-1"
              :disabled="isUpdating"
              @click="moveToNextStep"
            >
              <span class="i-lucide-chevron-right size-4" />
            </Button>
            <Button
              v-if="canComplete"
              v-tooltip="$t('KANBAN.MARK_COMPLETE')"
              variant="ghost"
              size="sm"
              class="shrink-0 !px-1 text-n-teal-11"
              :disabled="isUpdating"
              @click="markComplete"
            >
              <span class="i-lucide-check size-4" />
            </Button>
          </div>
        </div>

        <!-- Assigned Agents -->
        <div>
          <ContactDetailsItem compact :title="$t('KANBAN.ASSIGNED_AGENTS')">
            <template #button>
              <Button
                v-if="showSelfAssign"
                link
                xs
                icon="i-lucide-arrow-right"
                class="!gap-1"
                :label="$t('CONVERSATION_SIDEBAR.SELF_ASSIGN')"
                @click="assignToMe"
              />
            </template>
          </ContactDetailsItem>
          <TagMultiSelectComboBox
            :model-value="selectedAgentIds"
            :options="agentOptions"
            :placeholder="$t('KANBAN.SETTINGS.AGENTS_PLACEHOLDER')"
            :search-placeholder="$t('FORMS.MULTISELECT.ENTER_TO_SELECT')"
            :empty-state="$t('KANBAN.SETTINGS.NO_AGENTS_AVAILABLE')"
            @update:model-value="handleAgentsChange"
          />
        </div>

        <!-- Priority -->
        <div class="multiselect-wrap--small">
          <div class="flex items-center justify-between mb-1.5">
            <span class="text-sm font-medium text-n-slate-12">
              {{ $t('KANBAN.MODAL.PRIORITY_LABEL') }}
            </span>
            <div
              v-if="timeAgo"
              v-tooltip="stepChangedDate"
              class="flex items-center gap-1 text-xs text-slate-500 dark:text-slate-400"
            >
              <span class="i-lucide-clock size-3" />
              <span>{{ timeAgo }}</span>
            </div>
          </div>
          <KanbanContextDropdown
            :options="priorities"
            :selected-item="currentPriority"
            hide-search
            @select="handlePriorityChange"
          >
            <template #trigger="{ open }">
              <button
                class="w-full flex items-center gap-2 px-3 py-2 text-sm text-left rounded-lg outline outline-1 outline-n-strong hover:bg-slate-50 dark:hover:bg-slate-800 min-w-0"
                @click.stop="open"
              >
                <div
                  v-if="currentPriority?.icon"
                  :class="currentPriority.icon"
                  :style="{ color: currentPriority.color }"
                  class="size-4"
                />
                <span class="truncate text-slate-900 dark:text-slate-100">
                  {{
                    currentPriority?.name ||
                    $t('KANBAN.MODAL.PRIORITY_PLACEHOLDER')
                  }}
                </span>
              </button>
            </template>
          </KanbanContextDropdown>
        </div>

        <!-- Labels -->
        <div v-if="labelMenuItems.length">
          <ContactDetailsItem
            compact
            :title="$t('KANBAN.MODAL.LABELS_LABEL')"
          />
          <div
            class="flex flex-wrap items-center gap-1.5"
            @mouseleave="hoveredLabel = null"
          >
            <LabelItem
              v-for="label in selectedLabels"
              :key="label.id"
              :label="label"
              :is-hovered="hoveredLabel === label.id"
              @remove="handleRemoveLabel"
              @hover="hoveredLabel = label.id"
            />
            <AddLabel
              :label-menu-items="labelMenuItems"
              @update-label="handleLabelsChange"
            />
          </div>
        </div>

        <!-- Dates -->
        <KanbanTaskDatePicker
          :start-date="startDate"
          :due-date="dueDate"
          stacked
          @update:start-date="handleStartDateChange"
          @update:due-date="handleDueDateChange"
        />
      </div>
    </template>
  </div>
</template>
