<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const store = useStore();
const { t } = useI18n();

const dialogRef = ref(null);
const categoryName = ref('');
const isCreating = ref(false);

const isFormValid = computed(() => categoryName.value.trim().length > 0);

function open() {
  categoryName.value = '';
  dialogRef.value?.open();
}

async function handleConfirm() {
  if (!isFormValid.value) return;

  isCreating.value = true;
  try {
    await store.dispatch('internalChat/createCategory', {
      category: { name: categoryName.value.trim() },
    });
    useAlert(t('INTERNAL_CHAT.CATEGORY.CREATED'));
    dialogRef.value?.close();
  } catch {
    // error is handled by throwErrorMessage in the action
  } finally {
    isCreating.value = false;
  }
}

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('INTERNAL_CHAT.CATEGORY.CREATE')"
    :confirm-button-label="t('INTERNAL_CHAT.CATEGORY.CREATE')"
    :disable-confirm-button="!isFormValid"
    :is-loading="isCreating"
    @confirm="handleConfirm"
  >
    <div class="flex flex-col gap-4">
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('INTERNAL_CHAT.CATEGORY.NAME') }}
        </label>
        <input
          v-model="categoryName"
          type="text"
          class="w-full rounded-lg border border-n-slate-6 bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 placeholder-n-slate-10 outline-none focus:border-n-brand"
          :placeholder="t('INTERNAL_CHAT.CATEGORY.NAME_PLACEHOLDER')"
        />
      </div>
    </div>
  </Dialog>
</template>
