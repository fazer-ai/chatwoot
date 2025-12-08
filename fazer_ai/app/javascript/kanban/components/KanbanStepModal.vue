<script setup>
import { ref, watch, onMounted, computed, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ColorPicker from 'dashboard/components-next/colorpicker/ColorPicker.vue';
import { getRandomColor } from 'dashboard/helper/labelColor';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  step: {
    type: Object,
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
  canDelete: {
    type: Boolean,
    default: true,
  },
  boardName: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['close', 'save', 'delete']);

const { t } = useI18n();

const name = ref('');
const description = ref('');
const color = ref(getRandomColor());
const dialogRef = ref(null);
const deleteDialogRef = ref(null);
const discardDialogRef = ref(null);
const showDeleteDialog = ref(false);
const showDiscardDialog = ref(false);
const initialValues = ref({});

const isEditing = computed(() => !!props.step && !!props.step.id);

const copyId = async () => {
  await copyTextToClipboard(props.step.id);
  useAlert(t('COMPONENTS.CODE.COPY_SUCCESSFUL'));
};

const modalTitle = computed(() => {
  if (isEditing.value) {
    return props.boardName
      ? t('KANBAN.STEP_MODAL.EDIT_TITLE_WITH_BOARD', {
          boardName: props.boardName,
        })
      : t('KANBAN.STEP_MODAL.EDIT_TITLE');
  }
  return props.boardName
    ? t('KANBAN.STEP_MODAL.CREATE_TITLE_WITH_BOARD', {
        boardName: props.boardName,
      })
    : t('KANBAN.STEP_MODAL.CREATE_TITLE');
});

const openModal = () => {
  dialogRef.value?.open();
  if (isEditing.value) {
    initialValues.value = {
      name: props.step.name,
      description: props.step.description || '',
      color: props.step.color,
    };
  } else {
    initialValues.value = {
      name: '',
      description: '',
      color: getRandomColor(),
    };
  }
  name.value = initialValues.value.name;
  description.value = initialValues.value.description;
  color.value = initialValues.value.color;
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

watch(showDeleteDialog, val => {
  if (val) {
    deleteDialogRef.value?.open();
  } else {
    deleteDialogRef.value?.close();
  }
});

const onSave = () => {
  const payload = {
    name: name.value.trim().replace(/ +/g, ' '),
    description: description.value.trim(),
    color: color.value,
  };

  if (props.step) {
    payload.id = props.step.id;
  }

  emit('save', payload);
};

const onDelete = () => {
  showDeleteDialog.value = true;
  deleteDialogRef.value?.open();
};

const confirmDelete = () => {
  emit('delete', props.step.id);
};

const onDeleteDialogClose = () => {
  showDeleteDialog.value = false;
};

const hasChanges = computed(() => {
  return (
    name.value !== initialValues.value.name ||
    description.value !== initialValues.value.description ||
    color.value !== initialValues.value.color
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
    props.isDeleting
  );
});

const handleClickOutside = () => {
  if (props.isSaving || props.isDeleting) {
    return;
  }
  if (hasChanges.value && !showDeleteDialog.value && !showDiscardDialog.value) {
    showDiscardDialog.value = true;
  }
};
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="modalTitle"
    :ignore-click-outside="shouldIgnoreClickOutside"
    overflow-y-auto
    @close="handleClose"
    @click-outside="handleClickOutside"
  >
    <template #header-actions>
      <div v-if="isEditing" class="flex items-center gap-2 whitespace-nowrap">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('KANBAN.MODAL.ID_LABEL') }} {{ step.id }}
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
    <div class="flex flex-col gap-4">
      <label class="flex flex-col gap-2 text-sm font-medium text-n-slate-12">
        {{ t('KANBAN.STEP_MODAL.NAME_LABEL') }}
        <!-- NOTE: Autocomplete off to avoid browser autofill breaking scrollbar -->
        <Input
          v-model="name"
          :placeholder="t('KANBAN.STEP_MODAL.NAME_PLACEHOLDER')"
          maxlength="60"
          autocomplete="off"
          data-lpignore="true"
          data-1p-ignore="true"
        />
      </label>

      <Editor
        v-model="description"
        :label="t('KANBAN.STEP_MODAL.DESCRIPTION_LABEL')"
        :placeholder="t('KANBAN.STEP_MODAL.DESCRIPTION_PLACEHOLDER')"
        :max-length="120"
        enable-line-breaks
      />

      <div class="flex flex-col gap-2">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.STEP_MODAL.COLOR_LABEL') }}
        </label>
        <ColorPicker v-model="color" />
      </div>
    </div>
    <template #footer>
      <div class="flex justify-between w-full">
        <div v-if="isEditing && canDelete">
          <Button
            variant="ghost"
            color="slate"
            class="text-red-500 hover:text-red-600 hover:bg-red-50"
            :disabled="isSaving || isDeleting"
            type="button"
            @click="onDelete"
          >
            {{ t('KANBAN.STEP_MODAL.DELETE') }}
          </Button>
        </div>
        <div v-else />
        <div class="flex gap-2">
          <Button
            variant="ghost"
            :disabled="isSaving || isDeleting"
            @click="handleClose"
          >
            {{ t('KANBAN.STEP_MODAL.CANCEL') }}
          </Button>
          <Button
            :disabled="!name.trim() || isSaving || isDeleting"
            :is-loading="isSaving"
            type="submit"
            @click="onSave"
          >
            {{
              isEditing
                ? t('KANBAN.STEP_MODAL.UPDATE')
                : t('KANBAN.STEP_MODAL.CREATE')
            }}
          </Button>
        </div>
      </div>
    </template>
  </Dialog>

  <Dialog
    v-if="isEditing"
    ref="deleteDialogRef"
    type="alert"
    :title="t('KANBAN.STEP_MODAL.DELETE_TITLE')"
    :description="t('KANBAN.STEP_MODAL.DELETE_CONFIRMATION', { name: name })"
    :ignore-click-outside="isDeleting"
    @confirm="confirmDelete"
    @close="onDeleteDialogClose"
  >
    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          variant="faded"
          color="slate"
          :label="t('KANBAN.STEP_MODAL.CANCEL')"
          class="w-full"
          type="button"
          :disabled="isDeleting"
          @click="onDeleteDialogClose"
        />
        <Button
          color="ruby"
          :label="t('KANBAN.STEP_MODAL.DELETE')"
          class="w-full"
          :is-loading="isDeleting"
          :disabled="isDeleting"
          type="submit"
        />
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
