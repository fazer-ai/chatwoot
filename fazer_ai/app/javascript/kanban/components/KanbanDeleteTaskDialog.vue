<script setup>
import { ref, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  taskTitle: {
    type: String,
    default: '',
  },
  isDeleting: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['confirm', 'close']);
const { t } = useI18n();
const dialogRef = ref(null);

const open = () => {
  dialogRef.value?.open();
};

const close = () => {
  dialogRef.value?.close();
};

watch(
  () => props.show,
  val => {
    if (val) {
      open();
    } else {
      close();
    }
  }
);

onMounted(() => {
  if (props.show) {
    open();
  }
});

const onConfirm = () => {
  emit('confirm');
};

const onClose = () => {
  emit('close');
};
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="t('KANBAN.MODAL.DELETE_CONFIRMATION_TITLE')"
    :description="t('KANBAN.MODAL.DELETE_CONFIRMATION', { title: taskTitle })"
    :ignore-click-outside="isDeleting"
    overflow-y-auto
    @confirm="onConfirm"
    @close="onClose"
  >
    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          variant="faded"
          color="slate"
          :label="t('KANBAN.MODAL.CANCEL')"
          class="w-full"
          type="button"
          :disabled="isDeleting"
          @click="onClose"
        />
        <Button
          color="ruby"
          :label="t('KANBAN.MODAL.DELETE')"
          class="w-full"
          :is-loading="isDeleting"
          :disabled="isDeleting"
          type="submit"
        />
      </div>
    </template>
  </Dialog>
</template>
