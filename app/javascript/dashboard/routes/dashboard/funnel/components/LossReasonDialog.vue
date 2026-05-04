<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

defineProps({
  reasons: { type: Array, default: () => [] },
  isLoading: { type: Boolean, default: false },
  isSubmitting: { type: Boolean, default: false },
});

const emit = defineEmits(['confirm', 'close']);

const { t } = useI18n();

const dialogRef = ref(null);
const selectedId = ref('');

watch(
  () => dialogRef.value?.isOpen,
  isOpen => {
    if (!isOpen) selectedId.value = '';
  }
);

const onConfirm = () => {
  if (!selectedId.value) return;
  emit('confirm', Number(selectedId.value));
};

const onClose = () => {
  selectedId.value = '';
  emit('close');
};

defineExpose({
  open: () => dialogRef.value?.open(),
  close: () => dialogRef.value?.close(),
});
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="alert"
    width="md"
    :title="t('FUNNEL.LOSS_REASON_DIALOG.TITLE')"
    :description="t('FUNNEL.LOSS_REASON_DIALOG.DESCRIPTION')"
    :confirm-button-label="t('FUNNEL.LOSS_REASON_DIALOG.CONFIRM')"
    :cancel-button-label="t('FUNNEL.LOSS_REASON_DIALOG.CANCEL')"
    :disable-confirm-button="!selectedId || isLoading"
    :is-loading="isSubmitting"
    @confirm="onConfirm"
    @close="onClose"
  >
    <div class="flex flex-col gap-2">
      <label v-if="isLoading" class="text-sm text-n-slate-11">
        {{ t('FUNNEL.LOSS_REASON_DIALOG.LOADING') }}
      </label>
      <template v-else>
        <label
          v-for="reason in reasons"
          :key="reason.id"
          class="flex items-center gap-2 px-3 py-2 rounded-md cursor-pointer hover:bg-n-alpha-2"
          :class="
            String(selectedId) === String(reason.id)
              ? 'bg-n-alpha-2 ring-1 ring-n-blue-9'
              : ''
          "
        >
          <input
            v-model="selectedId"
            type="radio"
            :value="String(reason.id)"
            name="loss-reason"
            class="mr-1"
          />
          <span class="text-sm text-n-slate-12">{{ reason.name }}</span>
        </label>
        <p v-if="!reasons.length" class="text-sm text-n-slate-11">
          {{ t('FUNNEL.LOSS_REASON_DIALOG.EMPTY') }}
        </p>
      </template>
    </div>
  </Dialog>
</template>
