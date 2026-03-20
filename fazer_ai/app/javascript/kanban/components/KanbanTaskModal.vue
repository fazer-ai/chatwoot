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
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import TagInput from 'dashboard/components-next/taginput/TagInput.vue';
import LabelItem from 'dashboard/components-next/label/LabelItem.vue';
import AddLabel from 'dashboard/components-next/label/AddLabel.vue';
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

const labelMenuItems = computed(() =>
  accountLabels.value.map(label => ({
    label: label.title,
    value: label.id,
    thumbnail: { name: label.title, color: label.color },
    isSelected: selectedLabels.value.some(l => l.title === label.title),
    action: 'label',
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
    value: agent.id,
    label: agent.name,
  }))
);

const currentUser = useMapGetter('getCurrentUser');

const showSelfAssign = computed(() => {
  if (!currentUser.value) return false;

  if (selectedAgents.value.includes(currentUser.value.id)) return false;

  return agentOptions.value.some(agent => agent.value === currentUser.value.id);
});

const onSelfAssign = () => {
  if (!currentUser.value) return;

  if (!selectedAgents.value.includes(currentUser.value.id)) {
    selectedAgents.value.push(currentUser.value.id);
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
    selectedAgents.value = (props.task.assigned_agents || []).map(a => a.id);
    selectedContacts.value = [...(props.task.contacts || [])];
    selectedConversations.value = [...(props.task.conversations || [])];
    contactOptions.value = [...selectedContacts.value];
    conversationOptions.value = [...selectedConversations.value];
    startDate.value = parseDate(props.task.start_date);
    dueDate.value = parseDate(props.task.due_date);
    const taskLabelTitles = props.task.labels || [];
    selectedLabels.value = accountLabels.value.filter(label =>
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
    selectedAgents.value = (props.duplicateTask.assigned_agents || []).map(
      a => a.id
    );
    selectedContacts.value = [...(props.duplicateTask.contacts || [])];
    selectedConversations.value = [
      ...(props.duplicateTask.conversations || []),
    ];
    contactOptions.value = [...selectedContacts.value];
    conversationOptions.value = [...selectedConversations.value];
    startDate.value = parseDate(props.duplicateTask.start_date);
    dueDate.value = parseDate(props.duplicateTask.due_date);
    const dupLabelTitles = props.duplicateTask.labels || [];
    selectedLabels.value = accountLabels.value.filter(label =>
      dupLabelTitles.includes(label.title)
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

// TagInput computeds and handlers for conversations
const selectedConversationLabels = computed(() =>
  selectedConversations.value.map(c => `#${c.display_id} - ${c.contact.name}`)
);

const conversationMenuItems = computed(() =>
  conversationOptions.value
    .filter(c => !selectedConversations.value.find(s => s.id === c.id))
    .map(c => ({
      action: 'select',
      value: c.id,
      label: `#${c.display_id} - ${c.contact.name}`,
    }))
);

const handleAddConversation = menuItem => {
  const conv = conversationOptions.value.find(c => c.id === menuItem.value);
  if (conv && !selectedConversations.value.find(s => s.id === conv.id)) {
    selectedConversations.value.push(conv);
  }
};

const handleRemoveConversation = index => {
  selectedConversations.value.splice(index, 1);
};

const onSearchConversationsInput = e => {
  onSearchConversations(e.target?.value || '');
};

// TagInput computeds and handlers for contacts
const selectedContactLabels = computed(() =>
  selectedContacts.value.map(c => c.name)
);

const contactMenuItems = computed(() =>
  contactOptions.value
    .filter(c => !selectedContacts.value.find(s => s.id === c.id))
    .map(c => ({
      action: 'select',
      value: c.id,
      label: c.name,
      thumbnail: { name: c.name, src: c.avatar_url },
    }))
);

const handleAddContact = menuItem => {
  const contact = contactOptions.value.find(c => c.id === menuItem.value);
  if (contact && !selectedContacts.value.find(s => s.id === contact.id)) {
    selectedContacts.value.push(contact);
  }
};

const handleRemoveContact = index => {
  selectedContacts.value.splice(index, 1);
};

const onSearchContactsInput = e => {
  onSearchContacts(e.target?.value || '');
};

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
    assigned_agent_ids: selectedAgents.value,
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
    const newAgentIds = selectedAgents.value.slice().sort().join(',');
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

const hoveredLabel = ref(null);

const handleLabelToggle = ({ value: labelId }) => {
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
};

const handleRemoveLabel = label => {
  selectedLabels.value = selectedLabels.value.filter(
    l => l.title !== label.title
  );
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
          <TagMultiSelectComboBox
            :model-value="selectedAgents"
            :options="agentOptions"
            :placeholder="t('KANBAN.MODAL.AGENTS_PLACEHOLDER')"
            :search-placeholder="t('FORMS.MULTISELECT.ENTER_TO_SELECT')"
            :empty-state="t('KANBAN.MODAL.NO_AGENTS_AVAILABLE')"
            @update:model-value="selectedAgents = [...$event]"
          />
        </div>

        <div class="flex flex-col gap-2">
          <span class="text-sm font-medium text-n-slate-12 select-none">
            {{ t('KANBAN.MODAL.LABELS_LABEL') }}
          </span>
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
              @update-label="handleLabelToggle"
            />
          </div>
        </div>

        <div class="flex flex-col gap-2">
          <span class="text-sm font-medium text-n-slate-12 select-none">
            {{ t('KANBAN.MODAL.CONVERSATIONS_LABEL') }}
          </span>
          <TagInput
            :model-value="selectedConversationLabels"
            :menu-items="conversationMenuItems"
            :placeholder="t('KANBAN.MODAL.CONVERSATIONS_PLACEHOLDER')"
            :is-loading="isSearchingConversations"
            show-dropdown
            skip-label-dedup
            :auto-open-dropdown="false"
            @add="handleAddConversation"
            @remove="handleRemoveConversation"
            @input="onSearchConversationsInput"
          />
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
        </div>

        <div class="flex flex-col gap-2">
          <span class="text-sm font-medium text-n-slate-12 select-none">
            {{ t('KANBAN.MODAL.CONTACTS_LABEL') }}
          </span>
          <TagInput
            :model-value="selectedContactLabels"
            :menu-items="contactMenuItems"
            :placeholder="t('KANBAN.MODAL.CONTACTS_PLACEHOLDER')"
            :is-loading="isSearchingContacts"
            show-dropdown
            skip-label-dedup
            :auto-open-dropdown="false"
            @add="handleAddContact"
            @remove="handleRemoveContact"
            @input="onSearchContactsInput"
          />
        </div>

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
