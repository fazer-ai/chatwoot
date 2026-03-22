<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const store = useStore();
const { t } = useI18n();

const dialogRef = ref(null);
const channelName = ref('');
const channelDescription = ref('');
const channelType = ref('public_channel');
const categoryId = ref('');
const isCreating = ref(false);

const categories = computed(
  () => store.getters['internalChat/getCategories'] || []
);

const isFormValid = computed(() => channelName.value.trim().length > 0);

function open() {
  channelName.value = '';
  channelDescription.value = '';
  channelType.value = 'public_channel';
  categoryId.value = '';
  dialogRef.value?.open();
}

async function handleConfirm() {
  if (!isFormValid.value) return;

  isCreating.value = true;
  try {
    await store.dispatch('internalChat/create', {
      channel: {
        name: channelName.value.trim(),
        description: channelDescription.value.trim(),
        channel_type: channelType.value,
        category_id: categoryId.value || null,
        member_ids: [],
      },
    });
    useAlert(t('INTERNAL_CHAT.CHANNEL.CREATED'));
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
    :title="t('INTERNAL_CHAT.NEW_CHANNEL')"
    :confirm-button-label="t('INTERNAL_CHAT.NEW_CHANNEL')"
    :disable-confirm-button="!isFormValid"
    :is-loading="isCreating"
    @confirm="handleConfirm"
  >
    <div class="flex flex-col gap-4">
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('INTERNAL_CHAT.CHANNEL.NAME') }}
        </label>
        <input
          v-model="channelName"
          type="text"
          class="w-full rounded-lg border border-n-slate-6 bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 placeholder-n-slate-10 outline-none focus:border-n-brand"
          :placeholder="t('INTERNAL_CHAT.CHANNEL.NAME')"
        />
      </div>
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('INTERNAL_CHAT.CHANNEL.DESCRIPTION') }}
        </label>
        <textarea
          v-model="channelDescription"
          rows="3"
          class="w-full rounded-lg border border-n-slate-6 bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 placeholder-n-slate-10 outline-none focus:border-n-brand resize-none"
          :placeholder="t('INTERNAL_CHAT.CHANNEL.DESCRIPTION')"
        />
      </div>
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('INTERNAL_CHAT.CHANNEL.TYPE') }}
        </label>
        <select
          v-model="channelType"
          class="w-full rounded-lg border border-n-slate-6 bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand"
        >
          <option value="public_channel">
            {{ t('INTERNAL_CHAT.CHANNEL.PUBLIC') }}
          </option>
          <option value="private_channel">
            {{ t('INTERNAL_CHAT.CHANNEL.PRIVATE') }}
          </option>
        </select>
      </div>
      <div v-if="categories.length > 0" class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('INTERNAL_CHAT.CATEGORY.NAME') }}
        </label>
        <select
          v-model="categoryId"
          class="w-full rounded-lg border border-n-slate-6 bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand"
        >
          <option value="">
            {{ t('INTERNAL_CHAT.CATEGORY.NONE') }}
          </option>
          <option v-for="cat in categories" :key="cat.id" :value="cat.id">
            {{ cat.name }}
          </option>
        </select>
      </div>
    </div>
  </Dialog>
</template>
