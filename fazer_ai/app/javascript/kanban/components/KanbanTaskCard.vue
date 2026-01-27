<script setup>
import { computed, ref, onMounted, nextTick, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { shortTimestampFromDate } from 'shared/helpers/timeHelper';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import Button from 'dashboard/components-next/button/Button.vue';
import ThumbnailGroup from 'dashboard/components/widgets/ThumbnailGroup.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import KanbanContextDropdown from './KanbanContextDropdown.vue';
import TaskCardLabels from './TaskCardLabels.vue';
import { useKanban } from '../composables/useKanban';
import { KANBAN_PRIORITIES } from '../constants';

const props = defineProps({
  task: {
    type: Object,
    required: true,
  },
  allSteps: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['delete', 'update', 'duplicate', 'move']);

const { t } = useI18n();
const { priorities } = useKanban();
const { formatMessage } = useMessageFormatter();
const route = useRoute();
const router = useRouter();

const accountId = computed(() => route.params.accountId);

const getContactUrl = contact => {
  return frontendURL(`accounts/${accountId.value}/contacts/${contact.id}`);
};

const getConversationUrl = conversation => {
  return frontendURL(
    `accounts/${accountId.value}/conversations/${conversation.display_id}`
  );
};

const getPriority = priority =>
  KANBAN_PRIORITIES.find(p => p.id === priority) ||
  KANBAN_PRIORITIES.find(p => p.id === null);

const isNoPriority = computed(() => {
  return props.task.priority === null || props.task.priority === undefined;
});

const hasDueDate = computed(() => !!props.task.due_date);

const isOverdue = computed(() => props.task.date_status === 'overdue');
const isDueSoon = computed(() => props.task.date_status === 'due_soon');

const isSameDay = (date1, date2) =>
  date1.getFullYear() === date2.getFullYear() &&
  date1.getMonth() === date2.getMonth() &&
  date1.getDate() === date2.getDate();

const getRelativeDay = dateStr => {
  if (!dateStr) return null;
  const date = new Date(dateStr);
  const today = new Date();

  if (isSameDay(date, today)) return 'today';

  const yesterday = new Date(today);
  yesterday.setDate(today.getDate() - 1);
  if (isSameDay(date, yesterday)) return 'yesterday';

  const tomorrow = new Date(today);
  tomorrow.setDate(today.getDate() + 1);
  if (isSameDay(date, tomorrow)) return 'tomorrow';

  return null;
};

const formatDate = dateStr => {
  if (!dateStr) return '';

  const relativeDay = getRelativeDay(dateStr);
  if (relativeDay === 'today') return t('KANBAN.DATE.TODAY');
  if (relativeDay === 'yesterday') return t('KANBAN.DATE.YESTERDAY');
  if (relativeDay === 'tomorrow') return t('KANBAN.DATE.TOMORROW');

  const date = new Date(dateStr);
  const currentYear = new Date().getFullYear();
  const dateYear = date.getFullYear();

  const options = {
    month: 'short',
    day: 'numeric',
  };

  if (dateYear !== currentYear) {
    options.year = 'numeric';
  }

  return date.toLocaleDateString(undefined, options);
};

const formatDateWithTime = dateStr => {
  if (!dateStr) return '';
  const date = new Date(dateStr);
  const currentYear = new Date().getFullYear();
  const dateYear = date.getFullYear();

  const options = {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  };

  if (dateYear !== currentYear) {
    options.year = 'numeric';
  }

  return date.toLocaleString(undefined, options);
};

const dueDateDisplay = computed(() => {
  if (!hasDueDate.value) return '';
  return formatDate(props.task.due_date);
});

const dueDateTooltip = computed(() => {
  if (!hasDueDate.value) return '';
  return t('KANBAN.DATE.DUE_AT', {
    date: formatDateWithTime(props.task.due_date),
  });
});

const dateStatusClasses = computed(() => {
  if (isOverdue.value) return 'text-n-ruby-11 bg-n-ruby-3';
  if (isDueSoon.value) return 'text-n-amber-11 bg-n-amber-3';
  return 'text-n-slate-11 bg-n-slate-3';
});

const dateStatusIcon = computed(() => {
  if (isOverdue.value) return 'i-lucide-alert-circle';
  if (isDueSoon.value) return 'i-lucide-clock';
  return 'i-lucide-calendar';
});

const timeAgo = computed(() => {
  const date = props.task.step_changed_at || props.task.created_at;
  const unixTime = new Date(date).getTime() / 1000;
  return shortTimestampFromDate({ time: unixTime, withAgo: false, t });
});

const stepChangedDate = computed(() => {
  const date = props.task.step_changed_at || props.task.created_at;
  const formattedDate = new Date(date).toLocaleString();

  if (props.task.status === 'completed') {
    return t('KANBAN.WON_AT_TOOLTIP', { date: formattedDate });
  }
  if (props.task.status === 'cancelled') {
    return t('KANBAN.LOST_AT_TOOLTIP', { date: formattedDate });
  }
  if (props.task.step_changed_at) {
    return t('KANBAN.STEP_CHANGED_AT_TOOLTIP', { date: formattedDate });
  }
  return t('KANBAN.CREATED_AT_TOOLTIP', { date: formattedDate });
});

const assignedAgents = computed(
  () =>
    props.task.assigned_agents.map(agent => ({
      ...agent,
      thumbnail: agent.avatar_url,
    })) || []
);

const contacts = computed(() => props.task.contacts || []);
const conversations = computed(() => props.task.conversations || []);

const contactsAndConversations = computed(() => {
  const items = [];
  const contactIds = conversations.value.map(c => c.contact.id);

  contacts.value.forEach(contact => {
    if (!contactIds.includes(contact.id)) {
      items.push({ type: 'contact', data: contact });
    }
  });

  conversations.value.forEach(conversation => {
    items.push({ type: 'conversation', data: conversation });
  });

  return items;
});

const getVisibleAgents = agents => {
  if (!agents) return [];
  if (agents.length <= 4) return agents;
  return agents.slice(0, 3);
};

const getRemainingAgentsCount = agents => {
  const total = agents?.length || 0;
  if (total <= 4) return '';
  const remaining = total - 3;
  return `+${remaining}`;
};

const priorityLabel = computed(() => {
  const key = props.task.priority ? props.task.priority.toUpperCase() : 'NONE';
  const priorityName = t(`KANBAN.PRIORITY.${key}`);
  return t('KANBAN.PRIORITY.TOOLTIP_PREFIX', { priority: priorityName });
});

const priorityColor = computed(() => {
  return getPriority(props.task.priority).color;
});

const priorityIcon = computed(() => {
  return getPriority(props.task.priority).icon;
});

const statusIcon = computed(() => {
  if (props.task.status === 'completed') return 'i-lucide-check-circle-2';
  if (props.task.status === 'cancelled') return 'i-lucide-x-circle';
  return null;
});

const statusColor = computed(() => {
  if (props.task.status === 'completed') return 'text-n-teal-11';
  if (props.task.status === 'cancelled') return 'text-n-ruby-11';
  return '';
});

const statusTooltip = computed(() => {
  if (props.task.status === 'completed') return t('KANBAN.STATUS.COMPLETED');
  if (props.task.status === 'cancelled') return t('KANBAN.STATUS.CANCELLED');
  return '';
});

const isRenaming = ref(false);
const titleInputRef = ref(null);

const onInlineEdit = () => {
  isRenaming.value = true;
  nextTick(() => {
    if (titleInputRef.value) {
      titleInputRef.value.focus();
      const range = document.createRange();
      range.selectNodeContents(titleInputRef.value);
      range.collapse(false);
      const sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
    }
  });
};

const onSaveTitle = () => {
  if (!isRenaming.value) return;
  const newTitle = titleInputRef.value?.innerText?.trim();

  if (newTitle && newTitle !== props.task.title) {
    emit('update', { task: { ...props.task, title: newTitle } });
  } else if (titleInputRef.value) {
    titleInputRef.value.innerText = props.task.title;
  }
  isRenaming.value = false;
};

const onCancelEdit = () => {
  if (titleInputRef.value) {
    titleInputRef.value.innerText = props.task.title;
  }
  isRenaming.value = false;
  titleInputRef.value?.blur();
};

const onTitleKeydown = event => {
  if (event.key === 'Enter') {
    event.preventDefault();
    onSaveTitle();
    return;
  }
  if (event.key === 'Escape') {
    onCancelEdit();
    return;
  }

  const MAX_LENGTH = 255;
  const text = event.target.innerText;
  const isControlKey =
    [
      'Backspace',
      'Delete',
      'ArrowLeft',
      'ArrowRight',
      'ArrowUp',
      'ArrowDown',
      'Home',
      'End',
    ].includes(event.key) ||
    event.ctrlKey ||
    event.metaKey;

  if (text.length >= MAX_LENGTH && !isControlKey) {
    event.preventDefault();
  }
};

const onTitlePaste = event => {
  event.preventDefault();
  const MAX_LENGTH = 255;
  const text = (event.clipboardData || window.clipboardData).getData('text');
  const currentText = event.target.innerText;
  const selection = window.getSelection();
  const selectedText = selection.toString();

  const remainingSpace =
    MAX_LENGTH - (currentText.length - selectedText.length);

  if (remainingSpace <= 0) return;

  const textToPaste = text.substring(0, remainingSpace);
  document.execCommand('insertText', false, textToPaste);
};

const onDuplicate = () => {
  emit('duplicate', props.task);
};

const onDelete = () => {
  emit('delete', props.task);
};

const isExpanded = ref(false);
const showToggle = ref(false);
const descriptionRef = ref(null);

const checkOverflow = () => {
  const el = descriptionRef.value;
  if (el && !isExpanded.value) {
    showToggle.value = el.scrollHeight > el.clientHeight;
  }
};

watch(
  () => props.task.description,
  () => {
    nextTick(checkOverflow);
  }
);

onMounted(() => {
  checkOverflow();
});

const toggleDescription = () => {
  isExpanded.value = !isExpanded.value;
};

const onPriorityChange = item => {
  emit('update', { task: { ...props.task, priority: item.id } });
};

const currentStep = computed(() => {
  return props.allSteps.find(s => s.id === props.task.board_step_id) || {};
});

const stepColor = computed(() => {
  return currentStep.value.color;
});

const onStepChange = item => {
  emit('update', { task: { ...props.task, board_step_id: item.id } });
};

const nextStep = computed(() => {
  const currentIndex = props.allSteps.findIndex(
    s => s.id === props.task.board_step_id
  );
  if (currentIndex !== -1 && currentIndex < props.allSteps.length - 1) {
    return props.allSteps[currentIndex + 1];
  }
  return null;
});

const lastStep = computed(() => {
  if (props.allSteps.length === 0) return null;
  return props.allSteps[props.allSteps.length - 1];
});

const canComplete = computed(() => {
  if (!lastStep.value) return false;
  return props.task.board_step_id !== lastStep.value.id;
});

const onMoveToNextStep = () => {
  if (nextStep.value) {
    emit('move', { task: props.task, destinationStepId: nextStep.value.id });
  }
};

const onMarkComplete = () => {
  if (lastStep.value) {
    emit('move', { task: props.task, destinationStepId: lastStep.value.id });
  }
};

const taskUrl = computed(() => ({
  name: 'kanban_task_show',
  params: {
    accountId: accountId.value,
    boardId: route.params.boardId,
    taskId: props.task.id,
  },
}));

const handleLinkClick = (event, url) => {
  if (event.ctrlKey || event.metaKey || event.button === 1) {
    window.open(url, '_blank');
  } else {
    router.push(url);
  }
};

const handleDescriptionClick = event => {
  if (event.target.tagName === 'A') {
    event.stopPropagation();
  }
};
</script>

<template>
  <router-link
    :to="taskUrl"
    class="flex flex-col rounded-lg bg-white dark:bg-slate-800 shadow-sm transition-all hover:shadow-lg dark:hover:bg-slate-700/50 group relative cursor-pointer"
  >
    <header class="relative flex items-center gap-2 px-2.5 py-1.5">
      <div class="flex items-center gap-2 min-w-0 flex-1 overflow-hidden">
        <h4
          ref="titleInputRef"
          :contenteditable="isRenaming"
          class="text-sm font-medium break-words outline-none rounded -ml-1 px-1 border border-transparent min-w-0 flex-1"
          :class="{
            'cursor-text bg-n-slate-2 dark:bg-slate-900 border-n-brand/50':
              isRenaming,
          }"
          @blur="onSaveTitle"
          @keydown="onTitleKeydown"
          @paste="onTitlePaste"
          @click="isRenaming ? $event.stopPropagation() : null"
        >
          {{ task.title }}
        </h4>
        <span
          v-if="statusIcon"
          v-tooltip="statusTooltip"
          :class="[statusIcon, statusColor]"
          class="h-4 w-4 flex-shrink-0"
        />
      </div>
      <div
        class="absolute right-2 top-1.5 flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity"
      >
        <Button
          variant="ghost"
          size="xs"
          icon="i-lucide-trash-2"
          class="h-6 w-6 text-n-slate-11 hover:text-n-ruby-11 bg-white/80 dark:bg-slate-800/80 backdrop-blur-sm rounded shadow-sm"
          @click.prevent.stop="onDelete"
        />
        <Button
          variant="ghost"
          size="xs"
          icon="i-lucide-copy"
          class="h-6 w-6 text-n-slate-11 hover:text-n-slate-12 bg-white/80 dark:bg-slate-800/80 backdrop-blur-sm rounded shadow-sm"
          @click.prevent.stop="onDuplicate"
        />
        <Button
          variant="ghost"
          size="xs"
          icon="i-lucide-pencil"
          class="h-6 w-6 text-n-slate-11 hover:text-n-slate-12 bg-white/80 dark:bg-slate-800/80 backdrop-blur-sm rounded shadow-sm"
          @click.prevent.stop="onInlineEdit"
        />
      </div>
    </header>
    <div class="flex flex-col gap-1.5 px-2.5 pb-2.5">
      <!-- Contacts and Conversations Thumbnails -->
      <div
        v-if="contactsAndConversations.length || assignedAgents.length"
        class="flex items-center gap-4 -mt-0.5"
      >
        <div
          v-if="contactsAndConversations.length"
          class="flex items-center gap-1 overflow-visible min-w-0 p-0.5"
        >
          <template
            v-for="(item, index) in contactsAndConversations"
            :key="`${item.type}-${item.data.id}`"
          >
            <div
              v-if="item.type === 'contact'"
              v-tooltip="item.data.name"
              role="link"
              class="relative flex h-6 w-6 items-center justify-center rounded-full overflow-hidden bg-n-slate-4 outline outline-1 outline-n-background shadow cursor-pointer"
              :class="{
                'ltr:-ml-2 rtl:-mr-2': index > 0,
              }"
              @click.stop.prevent="
                handleLinkClick($event, getContactUrl(item.data))
              "
              @auxclick.stop.prevent="
                handleLinkClick($event, getContactUrl(item.data))
              "
            >
              <img
                v-if="item.data.avatar_url"
                :src="item.data.avatar_url"
                :alt="item.data.name"
                class="h-full w-full object-cover"
              />
              <span v-else class="text-xs font-medium text-n-slate-11">
                {{ item.data.name.charAt(0).toUpperCase() }}
              </span>
            </div>
            <div
              v-else-if="item.type === 'conversation'"
              v-tooltip="`${item.data.contact.name} - ${item.data.inbox.name}`"
              role="link"
              class="relative flex h-6 w-6 items-center justify-center cursor-pointer overflow-visible"
              :class="{
                'ltr:-ml-2 rtl:-mr-2': index > 0,
              }"
              @click.stop.prevent="
                handleLinkClick($event, getConversationUrl(item.data))
              "
              @auxclick.stop.prevent="
                handleLinkClick($event, getConversationUrl(item.data))
              "
            >
              <div
                class="h-full w-full rounded-full overflow-hidden bg-n-slate-4 outline outline-1 outline-n-background shadow"
              >
                <img
                  v-if="item.data.contact.avatar_url"
                  :src="item.data.contact.avatar_url"
                  :alt="item.data.contact.name"
                  class="h-full w-full object-cover"
                />
                <span
                  v-else
                  class="flex h-full w-full items-center justify-center text-xs font-medium text-n-slate-11"
                >
                  {{ item.data.contact.name.charAt(0).toUpperCase() }}
                </span>
              </div>
              <div
                class="absolute -bottom-1 -right-1 flex h-3.5 w-3.5 items-center justify-center rounded-full bg-white dark:bg-slate-800 outline outline-1 outline-n-background"
              >
                <ChannelIcon class="size-3.5" :inbox="item.data.inbox" />
              </div>
              <div
                v-if="item.data.status === 'resolved'"
                class="absolute -top-0.5 -right-0.5 flex h-2.5 w-2.5 items-center justify-center rounded-full bg-white dark:bg-slate-800 outline outline-1 outline-n-background z-10"
                :title="t('KANBAN.MODAL.RESOLVED_CONVERSATION')"
              >
                <span
                  class="i-lucide-check-circle size-2 text-green-600 dark:text-green-400"
                />
              </div>
            </div>
          </template>
        </div>

        <div
          v-if="assignedAgents.length"
          class="flex items-center justify-between gap-2 ml-auto flex-shrink-0"
        >
          <ThumbnailGroup
            :users-list="getVisibleAgents(assignedAgents)"
            :size="24"
            :show-more-thumbnails-count="assignedAgents.length > 4"
            :more-thumbnails-text="getRemainingAgentsCount(assignedAgents)"
          />
        </div>
      </div>

      <div
        v-if="task.description"
        ref="descriptionRef"
        v-dompurify-html="formatMessage(task.description, false)"
        class="text-xs text-n-slate-11 break-words [&_p]:my-0 [&_ul]:my-0 [&_ol]:my-0 [&_li]:my-0 [&_ul]:pl-4 [&_ol]:pl-4 [&_ul]:list-disc [&_ol]:list-decimal"
        :class="{ 'line-clamp-5': !isExpanded }"
        @click="handleDescriptionClick"
      />
      <button
        v-if="showToggle"
        class="text-xs font-medium text-n-brand hover:underline text-left w-fit"
        @click.stop.prevent="toggleDescription"
      >
        {{ isExpanded ? t('KANBAN.SHOW_LESS') : t('KANBAN.SHOW_MORE') }}
      </button>

      <TaskCardLabels v-if="task.labels?.length" :task-labels="task.labels" />

      <div class="flex items-center justify-between gap-2 mt-1">
        <div class="flex items-center gap-2 min-w-0">
          <KanbanContextDropdown
            :options="priorities"
            :selected-item="priorities.find(p => p.id === task.priority)"
            hide-search
            max-height="12rem"
            @select="onPriorityChange"
          >
            <template #trigger="{ open, isOpen }">
              <div
                v-if="priorityIcon"
                v-tooltip="priorityLabel"
                :class="[
                  priorityIcon,
                  isNoPriority && !isOpen
                    ? 'opacity-0 group-hover:opacity-100'
                    : '',
                ]"
                class="h-5 w-5 flex items-center justify-center transition-opacity cursor-pointer hover:bg-slate-100 dark:hover:bg-slate-700 rounded p-0.5"
                :style="{ color: priorityColor }"
                @click.stop.prevent="open"
              />
            </template>
          </KanbanContextDropdown>
        </div>
        <div class="flex items-center gap-2 ml-auto">
          <KanbanContextDropdown
            :options="allSteps"
            :selected-item="currentStep"
            hide-search
            :has-thumbnail="false"
            max-height="12rem"
            @select="onStepChange"
          >
            <template #trigger="{ open, isOpen }">
              <div
                :class="[!isOpen ? 'opacity-0 group-hover:opacity-100' : '']"
                class="h-5 w-5 flex items-center justify-center transition-opacity cursor-pointer hover:bg-slate-100 dark:hover:bg-slate-700 rounded p-0.5"
                @click.stop.prevent="open"
              >
                <div
                  class="w-2.5 h-2.5 rounded-full"
                  :style="{ backgroundColor: stepColor }"
                />
              </div>
            </template>
          </KanbanContextDropdown>
          <div
            v-if="nextStep"
            v-tooltip="t('KANBAN.MOVE_TO_NEXT_STEP', { step: nextStep.name })"
            class="h-5 w-5 flex items-center justify-center transition-opacity cursor-pointer hover:bg-slate-100 dark:hover:bg-slate-700 rounded p-0.5 opacity-0 group-hover:opacity-100"
            @click.stop.prevent="onMoveToNextStep"
          >
            <span class="i-lucide-arrow-right w-3 h-3 text-n-slate-11" />
          </div>
          <div
            v-if="canComplete"
            v-tooltip="t('KANBAN.MARK_COMPLETE')"
            class="h-5 w-5 flex items-center justify-center transition-opacity cursor-pointer hover:bg-slate-100 dark:hover:bg-slate-700 rounded p-0.5 opacity-0 group-hover:opacity-100"
            @click.stop.prevent="onMarkComplete"
          >
            <span class="i-lucide-check w-3 h-3 text-n-teal-11" />
          </div>
          <!-- Due date badge -->
          <div
            v-if="hasDueDate"
            v-tooltip="dueDateTooltip"
            class="flex items-center gap-1 text-xs px-1.5 py-0.5 rounded-full whitespace-nowrap"
            :class="dateStatusClasses"
          >
            <span :class="dateStatusIcon" class="h-3 w-3 flex-shrink-0" />
            <span>{{ dueDateDisplay }}</span>
          </div>
          <div
            v-if="timeAgo"
            v-tooltip="stepChangedDate"
            class="flex items-center gap-1 text-xs text-n-slate-10"
          >
            <span class="i-lucide-clock h-3 w-3" />
            <span>{{ timeAgo }}</span>
          </div>
        </div>
      </div>
    </div>
  </router-link>
</template>
