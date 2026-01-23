<script setup>
import { ref, watch, onMounted, computed, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { BOARD_TEMPLATES } from 'kanban/constants';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  board: {
    type: Object,
    default: null,
  },
  isSaving: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['close', 'save']);

const dialogId = `kanban-board-modal-${Math.random().toString(36).substr(2, 9)}`;

const { t } = useI18n();

const name = ref('');
const description = ref('');
const dialogRef = ref(null);
const discardDialogRef = ref(null);
const showDiscardDialog = ref(false);
const isDiscarding = ref(false);
const discardAction = ref('close'); // 'close' or 'back'
const initialValues = ref({});
const selectedTemplate = ref(null);
const step = ref('details');

const isEditing = computed(() => !!props.board && !!props.board.id);

const modalTitle = computed(() => {
  if (step.value === 'template_selection') {
    return t('KANBAN.BOARD_MODAL.SELECT_TEMPLATE_TITLE');
  }
  if (isEditing.value) {
    return t('KANBAN.BOARD_MODAL.EDIT_TITLE');
  }
  return t('KANBAN.BOARD_MODAL.CREATE_TITLE');
});

const openModal = () => {
  dialogRef.value?.open();
  if (isEditing.value) {
    step.value = 'details';
    initialValues.value = {
      name: props.board.name,
      description: props.board.description || '',
    };
    name.value = initialValues.value.name;
    description.value = initialValues.value.description;
  } else {
    step.value = 'template_selection';
    selectedTemplate.value = null;
    initialValues.value = {
      name: '',
      description: '',
    };
    name.value = '';
    description.value = '';
  }
};

const onSave = () => {
  if (!name.value) return;

  const payload = {
    name: name.value,
    description: description.value,
  };

  if (isEditing.value) {
    payload.id = props.board.id;
  } else if (selectedTemplate.value) {
    payload.steps_attributes = selectedTemplate.value.steps_attributes.map(
      s => ({
        name: t(s.nameKey),
        color: s.color,
        cancelled: s.cancelled || false,
        tasks_attributes: s.tasks_attributes.map(task => ({
          title: t(task.titleKey),
          description: task.descriptionKey ? t(task.descriptionKey) : undefined,
          priority: task.priority,
        })),
      })
    );
  }

  emit('save', payload);
};

const selectTemplate = template => {
  if (props.isSaving) return;
  selectedTemplate.value = template;
  if (template) {
    name.value = t(template.nameKey);
    description.value = t(template.descriptionKey);
  } else {
    name.value = '';
    description.value = '';
  }
  step.value = 'details';
};

const hasChanges = computed(() => {
  if (step.value === 'template_selection') return false;

  return (
    name.value !== initialValues.value.name ||
    description.value !== initialValues.value.description
  );
});

const goBack = () => {
  if (hasChanges.value) {
    discardAction.value = 'back';
    showDiscardDialog.value = true;
  } else {
    step.value = 'template_selection';
  }
};

const shouldIgnoreClickOutside = computed(() => {
  return props.isSaving || showDiscardDialog.value || hasChanges.value;
});

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
      showDiscardDialog.value = false;
    }
  }
);

const handleClose = () => {
  if (props.isSaving || isDiscarding.value) {
    return;
  }

  if (hasChanges.value && !showDiscardDialog.value) {
    discardAction.value = 'close';
    showDiscardDialog.value = true;
  } else if (!hasChanges.value) {
    emit('close');
  }
};

const confirmDiscard = async () => {
  isDiscarding.value = true;
  showDiscardDialog.value = false;
  await nextTick();

  if (discardAction.value === 'back') {
    step.value = 'template_selection';
    selectedTemplate.value = null;
    name.value = '';
    description.value = '';
    initialValues.value = { name: '', description: '' };
  } else {
    emit('close');
  }

  setTimeout(() => {
    isDiscarding.value = false;
  }, 100);
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

const handleClickOutside = () => {
  if (props.isSaving || !props.show) return;

  if (hasChanges.value && !showDiscardDialog.value) {
    showDiscardDialog.value = true;
  }
};
</script>

<template>
  <Dialog
    :id="dialogId"
    ref="dialogRef"
    :title="modalTitle"
    width="3xl"
    overflow-y-auto
    :ignore-click-outside="shouldIgnoreClickOutside"
    @close="handleClose"
    @click-outside="handleClickOutside"
  >
    <div
      v-if="step === 'template_selection'"
      class="grid grid-cols-1 sm:grid-cols-2 gap-4"
    >
      <div
        class="flex flex-col gap-2 p-4 border rounded-xl border-n-slate-3 bg-n-alpha-1 transition-all"
        :class="{
          'hover:bg-n-alpha-2 hover:border-n-slate-4 cursor-pointer': !isSaving,
          'opacity-50 cursor-not-allowed': isSaving,
        }"
        @click="selectTemplate(null)"
      >
        <div
          class="flex items-center justify-center h-12 w-12 rounded-lg bg-n-slate-3 text-n-slate-11 mb-2"
        >
          <i class="i-lucide-layout w-6 h-6" />
        </div>
        <h3 class="text-base font-medium text-n-slate-12">
          {{ t('KANBAN.BOARD_MODAL.EMPTY_BOARD', 'Empty Board') }}
        </h3>
        <p class="text-sm text-n-slate-11">
          {{
            t(
              'KANBAN.BOARD_MODAL.EMPTY_BOARD_DESC',
              'Start from scratch with an empty board.'
            )
          }}
        </p>
      </div>

      <div
        v-for="template in BOARD_TEMPLATES"
        :key="template.id"
        class="relative flex flex-col gap-2 p-4 border rounded-xl border-n-slate-3 bg-n-alpha-1 transition-all"
        :class="{
          'hover:bg-n-alpha-2 hover:border-n-slate-4 cursor-pointer': !isSaving,
          'opacity-50 cursor-not-allowed':
            isSaving && selectedTemplate?.id !== template.id,
          'border-n-brand-9 bg-n-brand-1':
            isSaving && selectedTemplate?.id === template.id,
        }"
        @click="selectTemplate(template)"
      >
        <div
          v-if="isSaving && selectedTemplate?.id === template.id"
          class="absolute inset-0 flex items-center justify-center bg-n-alpha-1/50 rounded-xl z-10"
        >
          <Spinner class="text-n-brand-11" />
        </div>
        <div
          class="flex items-center justify-center h-12 w-12 rounded-lg bg-n-brand-3 text-n-brand-11 mb-2"
        >
          <i class="w-6 h-6" :class="template.icon" />
        </div>
        <h3 class="text-base font-medium text-n-slate-12">
          {{ t(template.nameKey) }}
        </h3>
        <p class="text-sm text-n-slate-11">
          {{ t(template.descriptionKey) }}
        </p>
      </div>
    </div>

    <div v-else class="flex flex-col gap-4">
      <label class="flex flex-col gap-2 text-sm font-medium text-n-slate-12">
        {{ t('KANBAN.BOARD_MODAL.NAME_LABEL') }}
        <Input
          v-model="name"
          :placeholder="t('KANBAN.BOARD_MODAL.NAME_PLACEHOLDER')"
          required
          autocomplete="off"
          data-lpignore="true"
          data-1p-ignore="true"
          maxlength="60"
        />
      </label>

      <Editor
        v-model="description"
        :label="t('KANBAN.BOARD_MODAL.DESCRIPTION_LABEL')"
        :placeholder="t('KANBAN.BOARD_MODAL.DESCRIPTION_PLACEHOLDER')"
        class="w-full"
        :max-length="120"
      />
    </div>

    <template #footer>
      <div class="flex justify-between items-center w-full">
        <div>
          <Button
            v-if="step === 'details' && !isEditing"
            variant="ghost"
            color="slate"
            @click="goBack"
          >
            {{ t('KANBAN.BOARD_MODAL.BACK') }}
          </Button>
        </div>
        <div class="flex gap-2">
          <Button variant="ghost" color="slate" @click="handleClose">
            {{ t('KANBAN.BOARD_MODAL.CANCEL') }}
          </Button>
          <Button
            v-if="step === 'details'"
            :is-loading="isSaving"
            :disabled="!name"
            @click="onSave"
          >
            {{
              isEditing
                ? t('KANBAN.BOARD_MODAL.UPDATE')
                : t('KANBAN.BOARD_MODAL.CREATE')
            }}
          </Button>
        </div>
      </div>
    </template>
  </Dialog>

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
