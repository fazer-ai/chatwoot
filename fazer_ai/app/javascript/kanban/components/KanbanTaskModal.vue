<script setup>
import { ref, computed, watch, onMounted, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { debounce } from '@chatwoot/utils';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import ContactAPI from 'dashboard/api/contacts';
import BoardsAPI from 'kanban/api/boards';
import KanbanDeleteTaskDialog from './KanbanDeleteTaskDialog.vue';
import KanbanContextDropdown from './KanbanContextDropdown.vue';
import KanbanTaskDatePicker from './KanbanTaskDatePicker.vue';
import { useKanban } from '../composables/useKanban';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  task: {
    type: Object,
    default: null,
  },
  duplicateTask: {
    type: Object,
    default: null,
  },
  stepId: {
    type: Number,
    default: null,
  },
  steps: {
    type: Array,
    default: () => [],
  },
  boardName: {
    type: String,
    default: '',
  },
  boardId: {
    type: Number,
    default: null,
  },
  isSaving: {
    type: Boolean,
    default: false,
  },
  isDeleting: {
    type: Boolean,
    default: false,
  },
  boardAgents: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['close', 'save', 'delete']);

const accountLabels = useMapGetter('labels/getLabels');

const dialogId = `kanban-task-modal-${Math.random().toString(36).substr(2, 9)}`;

const { t } = useI18n();
const { priorities } = useKanban();

const title = ref('');
const description = ref('');
const priority = ref(null);
const selectedStepId = ref('');
const selectedAgents = ref([]);
const selectedContacts = ref([]);
const contactOptions = ref([]);
const selectedConversations = ref([]);
const conversationOptions = ref([]);
const isSearchingContacts = ref(false);
const isSearchingConversations = ref(false);
const showDeleteDialog = ref(false);
const showDiscardDialog = ref(false);
const titleError = ref('');
const isDropdownOpen = ref(false);
const isPriorityDropdownOpen = ref(false);
const startDate = ref(null);
const dueDate = ref(null);
const selectedLabels = ref([]);

const labelOptions = computed(() =>
  accountLabels.value.map(label => ({
    id: label.id,
    title: label.title,
    color: label.color,
  }))
);

const stepOptions = computed(() =>
  props.steps.map(step => ({
    name: step.name,
    id: step.id,
    color: step.color,
  }))
);

const agentOptions = computed(() =>
  props.boardAgents.map(agent => ({
    id: agent.id,
    name: agent.name,
    avatar_url: agent.avatar_url,
    availability_status: agent.availability_status,
  }))
);

const currentUser = useMapGetter('getCurrentUser');

const showSelfAssign = computed(() => {
  if (!currentUser.value) return false;

  const isAssigned = selectedAgents.value.some(
    agent => agent.id === currentUser.value.id
  );
  if (isAssigned) return false;

  return agentOptions.value.some(agent => agent.id === currentUser.value.id);
});

const onSelfAssign = () => {
  if (!currentUser.value) return;

  const agentToAdd = agentOptions.value.find(
    agent => agent.id === currentUser.value.id
  );
  if (agentToAdd) {
    selectedAgents.value.push(agentToAdd);
  }
};

const selectedStep = computed(() => {
  return (
    stepOptions.value.find(
      s => String(s.id) === String(selectedStepId.value)
    ) || {}
  );
});

const handleStepSelect = step => {
  selectedStepId.value = String(step.id);
};

const selectedPriority = computed(() => {
  return priorities.value.find(p => p.id === priority.value) || {};
});

const handlePrioritySelect = p => {
  priority.value = p.id;
};

const lastStep = computed(() => {
  if (props.steps.length === 0) return null;
  return props.steps[props.steps.length - 1];
});

const canComplete = computed(() => {
  if (!lastStep.value || !props.task) return false;
  return String(selectedStepId.value) !== String(lastStep.value.id);
});

const onMarkComplete = () => {
  if (lastStep.value) {
    selectedStepId.value = String(lastStep.value.id);
  }
};

const hasReassignedConversations = computed(() => {
  if (!selectedConversations.value?.length) return false;

  const currentTaskId = props.task?.id;

  return selectedConversations.value.some(conv => {
    return conv.kanban_task_id && conv.kanban_task_id !== currentTaskId;
  });
});

const isConversationAssigned = conv => {
  const currentTaskId = props.task?.id;
  return conv.kanban_task_id && conv.kanban_task_id !== currentTaskId;
};

const copyId = async () => {
  await copyTextToClipboard(props.task.id);
  useAlert(t('COMPONENTS.CODE.COPY_SUCCESSFUL'));
};

const isEditing = computed(() => !!props.task);

const modalTitle = computed(() => {
  if (isEditing.value) {
    return props.boardName
      ? t('KANBAN.MODAL.EDIT_TITLE_WITH_BOARD', { boardName: props.boardName })
      : t('KANBAN.MODAL.EDIT_TITLE');
  }
  return props.boardName
    ? t('KANBAN.MODAL.CREATE_TITLE_WITH_BOARD', { boardName: props.boardName })
    : t('KANBAN.MODAL.CREATE_TITLE');
});

const dialogRef = ref(null);
const discardDialogRef = ref(null);

const parseDate = dateStr => {
  if (!dateStr) return null;
  const date = new Date(dateStr);
  return Number.isNaN(date.getTime()) ? null : date;
};

watch(title, () => {
  if (titleError.value) {
    titleError.value = '';
  }
});

const openModal = () => {
  dialogRef.value?.open();
  titleError.value = '';
  if (props.task) {
    title.value = props.task.title;
    description.value = props.task.description || '';
    priority.value = props.task.priority;
    selectedStepId.value = String(props.task.board_step_id);
    selectedAgents.value = [...(props.task.assigned_agents || [])];
    selectedContacts.value = [...(props.task.contacts || [])];
    selectedConversations.value = [...(props.task.conversations || [])];
    contactOptions.value = [...selectedContacts.value];
    conversationOptions.value = [...selectedConversations.value];
    startDate.value = parseDate(props.task.start_date);
    dueDate.value = parseDate(props.task.due_date);
    const taskLabelTitles = props.task.labels || [];
    selectedLabels.value = labelOptions.value.filter(label =>
      taskLabelTitles.includes(label.title)
    );
  } else if (props.duplicateTask) {
    const copySuffix = ` ${t('KANBAN.MODAL.COPY_SUFFIX')}`;
    const maxTitleLength = 255;
    const originalTitle = props.duplicateTask.title;
    const truncatedTitle = originalTitle.slice(
      0,
      maxTitleLength - copySuffix.length
    );
    title.value = `${truncatedTitle}${copySuffix}`;
    description.value = props.duplicateTask.description || '';
    priority.value = props.duplicateTask.priority;
    selectedStepId.value = String(props.duplicateTask.board_step_id);
    selectedAgents.value = [...(props.duplicateTask.assigned_agents || [])];
    selectedContacts.value = [...(props.duplicateTask.contacts || [])];
    selectedConversations.value = [
      ...(props.duplicateTask.conversations || []),
    ];
    contactOptions.value = [...selectedContacts.value];
    conversationOptions.value = [...selectedConversations.value];
    startDate.value = parseDate(props.duplicateTask.start_date);
    dueDate.value = parseDate(props.duplicateTask.due_date);
    const taskLabelTitles = props.duplicateTask.labels || [];
    selectedLabels.value = labelOptions.value.filter(label =>
      taskLabelTitles.includes(label.title)
    );
  } else {
    title.value = '';
    description.value = '';
    priority.value = null;
    selectedStepId.value = props.stepId ? String(props.stepId) : '';
    selectedAgents.value = [];
    selectedContacts.value = [];
    selectedConversations.value = [];
    contactOptions.value = [];
    conversationOptions.value = [];
    startDate.value = null;
    dueDate.value = null;
    selectedLabels.value = [];
  }
};

onMounted(() => {
  if (props.show) {
    openModal();
  }
});

watch(
  () => props.show,
  val => {
    if (val) {
      openModal();
    } else {
      dialogRef.value?.close();
    }
  }
);

const onSearchConversations = debounce(
  async query => {
    const trimmedQuery = query?.trim();
    isSearchingConversations.value = true;
    try {
      const boardId = props.task?.board_id || props.boardId;
      const { data } = await BoardsAPI.getConversations(boardId, trimmedQuery);
      conversationOptions.value = data.payload;
    } catch (error) {
      // ignore error
    } finally {
      isSearchingConversations.value = false;
    }
  },
  300,
  false
);

const onSearchContacts = debounce(
  async query => {
    const trimmedQuery = query?.trim();

    isSearchingContacts.value = true;
    try {
      const { data } = await ContactAPI.search(trimmedQuery);
      contactOptions.value = data.payload.map(contact => ({
        ...contact,
        avatar_url: contact.thumbnail,
      }));
    } catch (error) {
      // ignore error
    } finally {
      isSearchingContacts.value = false;
    }
  },
  300,
  false
);

watch(
  selectedConversations,
  newVal => {
    newVal.forEach(conv => {
      if (
        conv.contact &&
        !selectedContacts.value.find(c => c.id === conv.contact.id)
      ) {
        selectedContacts.value.push(conv.contact);
      }
    });
  },
  { deep: true }
);

watch(
  selectedContacts,
  (newVal, oldVal) => {
    const removedContacts = oldVal.filter(
      c => !newVal.find(nc => nc.id === c.id)
    );
    if (removedContacts.length > 0) {
      selectedConversations.value = selectedConversations.value.filter(conv => {
        return !removedContacts.find(rc => rc.id === conv.contact.id);
      });
    }
  },
  { deep: true }
);

// Normalizes date for API submission
const normalizeDate = date => {
  if (!date) return null;
  return new Date(date).toISOString();
};

const onSave = () => {
  if (!title.value.trim()) {
    titleError.value = t('KANBAN.MODAL.TITLE_REQUIRED');
    return;
  }

  const taskPayload = {
    title: title.value.trim().replace(/ +/g, ' '),
    description: description.value.trim().replace(/ +/g, ' '),
    priority: priority.value,
    board_step_id: selectedStepId.value,
    assigned_agent_ids: selectedAgents.value.map(a => a.id),
    contact_ids: selectedContacts.value.map(c => c.id),
    conversation_ids: selectedConversations.value.map(c => c.display_id),
    board_id: props.boardId,
    start_date: normalizeDate(startDate.value),
    due_date: normalizeDate(dueDate.value),
    labels: selectedLabels.value.map(l => l.title),
  };

  const payload = {
    task: taskPayload,
  };

  if (isEditing.value) {
    payload.task.id = props.task.id;
  }

  emit('save', payload);
};

const onDelete = () => {
  showDeleteDialog.value = true;
};

const confirmDelete = () => {
  emit('delete', props.task.id);
};

const onDeleteDialogClose = () => {
  showDeleteDialog.value = false;
};

const datesEqual = (date1, date2) => {
  if (!date1 && !date2) return true;
  if (!date1 || !date2) return false;
  return new Date(date1).getTime() === new Date(date2).getTime();
};

const hasChanges = computed(() => {
  if (props.task) {
    const currentAgentIds = (props.task.assigned_agents || [])
      .map(a => a.id)
      .sort()
      .join(',');
    const newAgentIds = selectedAgents.value
      .map(a => a.id)
      .sort()
      .join(',');
    const currentContactIds = (props.task.contacts || [])
      .map(c => c.id)
      .sort()
      .join(',');
    const newContactIds = selectedContacts.value
      .map(c => c.id)
      .sort()
      .join(',');
    const currentConversationIds = (props.task.conversations || [])
      .map(c => c.id)
      .sort((a, b) => a - b)
      .join(',');
    const newConversationIds = selectedConversations.value
      .map(c => c.id)
      .sort((a, b) => a - b)
      .join(',');
    const currentLabelTitles = [...(props.task.labels || [])].sort().join(',');
    const newLabelTitles = selectedLabels.value
      .map(l => l.title)
      .sort()
      .join(',');

    return (
      title.value !== props.task.title ||
      description.value !== (props.task.description || '') ||
      priority.value !== props.task.priority ||
      String(selectedStepId.value) !== String(props.task.board_step_id) ||
      currentAgentIds !== newAgentIds ||
      currentContactIds !== newContactIds ||
      currentConversationIds !== newConversationIds ||
      currentLabelTitles !== newLabelTitles ||
      !datesEqual(startDate.value, props.task.start_date) ||
      !datesEqual(dueDate.value, props.task.due_date)
    );
  }
  return (
    title.value !== '' ||
    description.value !== '' ||
    priority.value !== null ||
    String(selectedStepId.value) !==
      (props.stepId ? String(props.stepId) : '') ||
    selectedAgents.value.length > 0 ||
    selectedContacts.value.length > 0 ||
    selectedConversations.value.length > 0 ||
    selectedLabels.value.length > 0 ||
    startDate.value !== null ||
    dueDate.value !== null
  );
});

const handleClose = () => {
  if (props.isSaving || props.isDeleting) {
    return;
  }

  if (hasChanges.value) {
    showDiscardDialog.value = true;
  } else {
    emit('close');
  }
};

const confirmDiscard = () => {
  showDiscardDialog.value = false;
  emit('close');
};

const closeDiscardDialog = () => {
  showDiscardDialog.value = false;
};

watch(showDiscardDialog, async val => {
  if (val) {
    await nextTick();
    discardDialogRef.value?.open();
  }
});

const shouldIgnoreClickOutside = computed(() => {
  return (
    hasChanges.value ||
    showDeleteDialog.value ||
    showDiscardDialog.value ||
    props.isSaving ||
    props.isDeleting ||
    isDropdownOpen.value ||
    isPriorityDropdownOpen.value
  );
});

const handleClickOutside = () => {
  if (
    props.isSaving ||
    props.isDeleting ||
    isDropdownOpen.value ||
    isPriorityDropdownOpen.value
  ) {
    return;
  }
  if (hasChanges.value && !showDeleteDialog.value && !showDiscardDialog.value) {
    showDiscardDialog.value = true;
  }
};
</script>

<template>
  <Dialog
    :id="dialogId"
    ref="dialogRef"
    :title="modalTitle"
    :ignore-click-outside="shouldIgnoreClickOutside"
    overflow-y-auto
    width="3xl"
    @close="handleClose"
    @click-outside="handleClickOutside"
  >
    <template #header-actions>
      <div v-if="isEditing" class="flex items-center gap-2 whitespace-nowrap">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('KANBAN.MODAL.ID_LABEL') }} {{ task.id }}
        </span>
        <Button
          variant="ghost"
          color="slate"
          size="xs"
          icon="i-lucide-copy"
          @click="copyId"
        />
      </div>
    </template>
    <div class="grid grid-cols-2 gap-6">
      <div class="flex flex-col gap-4 h-full">
        <div class="flex flex-col gap-2">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('KANBAN.MODAL.TITLE_LABEL') }}
          </label>
          <Input
            v-model="title"
            :placeholder="t('KANBAN.MODAL.TITLE_PLACEHOLDER')"
            maxlength="255"
            :class="{ '!outline-n-ruby-7': titleError }"
          />
          <span v-if="titleError" class="text-xs text-n-ruby-11">
            {{ titleError }}
          </span>
        </div>

        <Editor
          v-model="description"
          :label="t('KANBAN.MODAL.DESCRIPTION_LABEL')"
          :placeholder="t('KANBAN.MODAL.DESCRIPTION_PLACEHOLDER')"
          :max-length="5000"
          show-character-count
          enable-line-breaks
          class="w-full [&_.ProseMirror-woot-style]:!min-h-[300px] [&_.ProseMirror-woot-style]:!max-h-[300px] [&_.ProseMirror-woot-style]:!overflow-y-auto"
        />
      </div>

      <div class="flex flex-col gap-4">
        <div class="flex flex-col gap-2">
          <div class="flex items-center justify-between">
            <span class="text-sm font-medium text-n-slate-12 select-none">
              {{ t('KANBAN.MODAL.AGENTS_LABEL') }}
            </span>
            <Button
              v-if="showSelfAssign"
              variant="link"
              size="xs"
              icon="i-lucide-arrow-right"
              class="!gap-1"
              @click="onSelfAssign"
            >
              {{ t('CONVERSATION_SIDEBAR.SELF_ASSIGN') }}
            </Button>
          </div>
          <multiselect
            v-model="selectedAgents"
            :options="agentOptions"
            track-by="id"
            label="name"
            multiple
            :close-on-select="false"
            :clear-on-select="false"
            :placeholder="t('KANBAN.MODAL.AGENTS_PLACEHOLDER')"
            select-label=""
            deselect-label=""
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
                  @mousedown.prevent.stop="remove(option)"
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
              {{ t('KANBAN.MODAL.NO_AGENTS_FOUND') }}
            </template>
            <template #noOptions>
              {{ t('KANBAN.MODAL.NO_AGENTS_AVAILABLE') }}
            </template>
          </multiselect>
        </div>

        <div class="flex flex-col gap-2">
          <span class="text-sm font-medium text-n-slate-12 select-none">
            {{ t('KANBAN.MODAL.LABELS_LABEL') }}
          </span>
          <multiselect
            v-model="selectedLabels"
            :options="labelOptions"
            track-by="id"
            label="title"
            multiple
            :close-on-select="false"
            :clear-on-select="false"
            :placeholder="t('KANBAN.MODAL.LABELS_PLACEHOLDER')"
            select-label=""
            deselect-label=""
            :selected-label="t('FORMS.MULTISELECT.SELECTED')"
            class="!mb-0"
          >
            <template #tag="{ option, remove }">
              <span
                class="inline-flex items-center gap-1 px-2 py-0.5 mr-0.5 mb-1 text-xs font-medium rounded bg-n-slate-3 border border-solid border-n-strong"
              >
                <span
                  class="size-2 rounded-full flex-shrink-0"
                  :style="{ backgroundColor: option.color }"
                />
                <span class="truncate max-w-24">{{ option.title }}</span>
                <button
                  type="button"
                  class="flex items-center justify-center p-0 ml-0.5 text-n-slate-10 hover:text-n-slate-12"
                  @mousedown.prevent.stop="remove(option)"
                >
                  <span class="i-lucide-x size-3" />
                </button>
              </span>
            </template>
            <template #option="{ option }">
              <div class="flex items-center gap-2 min-w-0">
                <div
                  class="w-2 h-2 rounded-full flex-shrink-0"
                  :style="{ backgroundColor: option.color }"
                />
                <span class="truncate">{{ option.title }}</span>
              </div>
            </template>
            <template #noResult>
              {{ t('KANBAN.MODAL.NO_LABELS_FOUND') }}
            </template>
            <template #noOptions>
              {{ t('KANBAN.MODAL.NO_LABELS_AVAILABLE') }}
            </template>
          </multiselect>
        </div>

        <label
          class="flex flex-col gap-2 text-sm font-medium text-n-slate-12"
          @click.prevent
        >
          {{ t('KANBAN.MODAL.CONVERSATIONS_LABEL') }}
          <multiselect
            v-model="selectedConversations"
            :options="conversationOptions"
            track-by="id"
            :custom-label="opt => `#${opt.display_id} - ${opt.contact.name}`"
            multiple
            :close-on-select="false"
            :clear-on-select="false"
            :placeholder="t('KANBAN.MODAL.CONVERSATIONS_PLACEHOLDER')"
            :loading="isSearchingConversations"
            :internal-search="false"
            select-label=""
            deselect-label=""
            :selected-label="t('FORMS.MULTISELECT.SELECTED')"
            class="!mb-0"
            @search-change="onSearchConversations"
          >
            <template #tag="{ option, remove }">
              <span
                class="multiselect__tag !inline-flex items-center gap-2 !relative !pl-7"
              >
                <div class="!absolute !left-1.5 !top-1/2 !-translate-y-1/2">
                  <Avatar
                    :src="option.contact.avatar_url"
                    :name="option.contact.name"
                    :size="16"
                  />
                  <div
                    class="absolute -bottom-1 -right-1 flex h-3.5 w-3.5 items-center justify-center rounded-full bg-white dark:bg-slate-800 outline outline-1 outline-n-background"
                  >
                    <ChannelIcon class="size-3 min-w-3" :inbox="option.inbox" />
                  </div>
                </div>
                <span
                  class="multiselect__tag-text !inline-block !max-w-[150px] !truncate"
                >
                  {{ `#${option.display_id} - ${option.contact.name}` }}
                </span>
                <span
                  v-if="option.status === 'resolved'"
                  class="i-lucide-check-circle size-3 text-green-600 dark:text-green-400 min-w-3"
                  :title="t('KANBAN.MODAL.RESOLVED_CONVERSATION')"
                />
                <span
                  v-if="isConversationAssigned(option)"
                  class="i-lucide-link size-3 text-amber-600 dark:text-amber-400 min-w-3"
                  :title="t('KANBAN.MODAL.ASSIGNED_CONVERSATION')"
                />
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
                <div class="relative flex-shrink-0">
                  <Avatar
                    :src="option.contact.avatar_url"
                    :name="option.contact.name"
                    :size="16"
                    class="leading-none text-center"
                  />
                  <div
                    class="absolute -bottom-1 -right-1 flex h-3.5 w-3.5 items-center justify-center rounded-full bg-white dark:bg-slate-800 outline outline-1 outline-n-background"
                  >
                    <ChannelIcon class="size-3 min-w-3" :inbox="option.inbox" />
                  </div>
                </div>
                <div class="flex flex-col min-w-0 overflow-hidden">
                  <div class="flex items-center gap-1">
                    <span class="font-medium text-sm truncate">
                      {{ '#' + option.display_id }}
                    </span>
                    <span
                      v-if="option.status === 'resolved'"
                      class="i-lucide-check-circle size-3 text-green-600 dark:text-green-400 min-w-3"
                      :title="t('KANBAN.MODAL.RESOLVED_CONVERSATION')"
                    />
                    <span
                      v-if="isConversationAssigned(option)"
                      class="i-lucide-link size-3 text-amber-600 dark:text-amber-400 min-w-3"
                      :title="t('KANBAN.MODAL.ASSIGNED_CONVERSATION')"
                    />
                  </div>
                  <span class="text-xs text-n-slate-11 truncate">
                    {{ option.inbox.name + ' - ' + option.contact.name }}
                  </span>
                </div>
              </div>
            </template>
            <template #noResult>
              {{ t('KANBAN.MODAL.NO_CONVERSATIONS_FOUND') }}
            </template>
            <template #noOptions>
              {{ t('KANBAN.MODAL.START_TYPING_CONVERSATIONS') }}
            </template>
          </multiselect>
          <div
            v-if="hasReassignedConversations"
            class="text-xs text-amber-600 dark:text-amber-400 flex items-start gap-1.5 mt-1"
          >
            <span
              class="i-lucide-alert-triangle size-3.5 mt-0.5 flex-shrink-0"
            />
            <span>{{
              t('KANBAN.MODAL.CONVERSATION_REASSIGNMENT_WARNING')
            }}</span>
          </div>
        </label>

        <label
          class="flex flex-col gap-2 text-sm font-medium text-n-slate-12"
          @click.prevent
        >
          {{ t('KANBAN.MODAL.CONTACTS_LABEL') }}
          <multiselect
            v-model="selectedContacts"
            :options="contactOptions"
            track-by="id"
            label="name"
            multiple
            :close-on-select="false"
            :clear-on-select="false"
            :placeholder="t('KANBAN.MODAL.CONTACTS_PLACEHOLDER')"
            :loading="isSearchingContacts"
            :internal-search="false"
            select-label=""
            deselect-label=""
            :selected-label="t('FORMS.MULTISELECT.SELECTED')"
            class="!mb-0"
            @search-change="onSearchContacts"
          >
            <template #tag="{ option, remove }">
              <span
                class="multiselect__tag !inline-flex items-center gap-2 !relative !pl-7"
              >
                <Avatar
                  :src="option.avatar_url"
                  :name="option.name"
                  :size="16"
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
                  class="leading-none text-center"
                />
                <span class="truncate">{{ option.name }}</span>
              </div>
            </template>
            <template #noResult>
              {{ t('KANBAN.MODAL.NO_CONTACTS_FOUND') }}
            </template>
            <template #noOptions>
              {{ t('KANBAN.MODAL.START_TYPING_CONTACTS') }}
            </template>
          </multiselect>
        </label>

        <!-- Date Pickers -->
        <KanbanTaskDatePicker
          :start-date="startDate"
          :due-date="dueDate"
          @update:start-date="startDate = $event"
          @update:due-date="dueDate = $event"
        />
      </div>
    </div>

    <template #footer>
      <div class="flex justify-between w-full">
        <div class="flex items-center gap-2">
          <Button
            v-if="isEditing"
            type="button"
            variant="ghost"
            color="ruby"
            :disabled="isSaving || isDeleting"
            @click="onDelete"
          >
            {{ t('KANBAN.MODAL.DELETE') }}
          </Button>
          <KanbanContextDropdown
            :options="stepOptions"
            :selected-item="selectedStep"
            hide-search
            :has-thumbnail="false"
            max-height="12rem"
            :teleport-to="`#${dialogId}`"
            @select="handleStepSelect"
            @open="isDropdownOpen = true"
            @close="isDropdownOpen = false"
          >
            <template #trigger="{ open }">
              <Button
                variant="ghost"
                size="sm"
                class="text-n-slate-12 max-w-[12rem]"
                @click.stop="open"
              >
                <div class="flex items-center gap-2 min-w-0">
                  <div
                    class="w-2 h-2 rounded-full flex-shrink-0"
                    :style="{ backgroundColor: selectedStep.color }"
                  />
                  <span class="truncate">
                    {{
                      selectedStep.name || t('KANBAN.MODAL.STEP_PLACEHOLDER')
                    }}
                  </span>
                </div>
              </Button>
            </template>
          </KanbanContextDropdown>
          <Button
            v-if="canComplete"
            v-tooltip="{
              content: t('KANBAN.MARK_COMPLETE'),
              container: `#${dialogId}`,
            }"
            variant="ghost"
            size="sm"
            icon="i-lucide-check"
            class="text-n-teal-11"
            :disabled="isSaving || isDeleting"
            @click="onMarkComplete"
          />
          <KanbanContextDropdown
            :options="priorities"
            :selected-item="selectedPriority"
            hide-search
            max-height="12rem"
            :teleport-to="`#${dialogId}`"
            @select="handlePrioritySelect"
            @open="isPriorityDropdownOpen = true"
            @close="isPriorityDropdownOpen = false"
          >
            <template #trigger="{ open }">
              <Button
                variant="ghost"
                size="sm"
                class="text-n-slate-12 max-w-[12rem]"
                @click.stop="open"
              >
                <div class="flex items-center gap-2 min-w-0">
                  <div
                    v-if="selectedPriority.icon"
                    :class="selectedPriority.icon"
                    :style="{ color: selectedPriority.color }"
                    class="w-4 h-4"
                  />
                  <span class="truncate">
                    {{
                      selectedPriority.name ||
                      t('KANBAN.MODAL.PRIORITY_PLACEHOLDER')
                    }}
                  </span>
                </div>
              </Button>
            </template>
          </KanbanContextDropdown>
        </div>

        <div class="flex gap-2">
          <Button
            variant="ghost"
            :disabled="isSaving || isDeleting"
            @click="handleClose"
          >
            {{ t('KANBAN.MODAL.CANCEL') }}
          </Button>
          <Button
            :disabled="isSaving || isDeleting"
            :is-loading="isSaving"
            type="submit"
            @click="onSave"
          >
            {{
              isEditing ? t('KANBAN.MODAL.UPDATE') : t('KANBAN.MODAL.CREATE')
            }}
          </Button>
        </div>
      </div>
    </template>
  </Dialog>

  <KanbanDeleteTaskDialog
    :show="showDeleteDialog"
    :task-title="title"
    :is-deleting="isDeleting"
    @confirm="confirmDelete"
    @close="onDeleteDialogClose"
  />

  <Dialog
    v-if="showDiscardDialog"
    ref="discardDialogRef"
    type="alert"
    :title="t('KANBAN.MODAL.DISCARD_TITLE')"
    :description="t('KANBAN.MODAL.DISCARD_CONFIRMATION')"
    :confirm-button-label="t('KANBAN.MODAL.DISCARD')"
    @confirm="confirmDiscard"
    @close="closeDiscardDialog"
  />
</template>
