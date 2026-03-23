<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import NextSelect from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const emit = defineEmits(['submit']);

const { t } = useI18n();

const dialogRef = ref(null);
const confirmDiscardRef = ref(null);

const question = ref('');
const options = ref([{ text: '' }, { text: '' }]);
const multipleChoice = ref(false);
const duration = ref('24h');
const publicResults = ref(true);
const isSubmitting = ref(false);

const durationOptions = computed(() => [
  { value: '24h', label: t('INTERNAL_CHAT.POLL.DURATION_24H') },
  { value: '7d', label: t('INTERNAL_CHAT.POLL.DURATION_7D') },
  { value: '14d', label: t('INTERNAL_CHAT.POLL.DURATION_14D') },
  { value: '30d', label: t('INTERNAL_CHAT.POLL.DURATION_30D') },
]);

const MAX_OPTIONS = 10;

const canSubmit = computed(() => {
  const filledOptions = options.value.filter(o => o.text.trim().length > 0);
  return (
    question.value.trim().length > 0 &&
    filledOptions.length >= 2 &&
    !isSubmitting.value
  );
});

const hasUnsavedChanges = computed(() => {
  const hasQuestion = question.value.trim().length > 0;
  const hasOptionText = options.value.some(o => o.text.trim().length > 0);
  const settingsChanged =
    multipleChoice.value !== false ||
    publicResults.value !== true ||
    duration.value !== '24h';
  return hasQuestion || hasOptionText || settingsChanged;
});

function addOption() {
  if (options.value.length < MAX_OPTIONS) {
    options.value.push({ text: '' });
  }
}

function removeOption(index) {
  if (options.value.length > 2) {
    options.value.splice(index, 1);
  }
}

function computeExpiresAt(durationValue) {
  const now = new Date();
  const match = durationValue.match(/^(\d+)(h|d)$/);
  if (!match) return null;
  const [, amount, unit] = match;
  if (unit === 'h') now.setHours(now.getHours() + parseInt(amount, 10));
  else now.setDate(now.getDate() + parseInt(amount, 10));
  return now.toISOString();
}

function resetForm() {
  question.value = '';
  options.value = [{ text: '' }, { text: '' }];
  multipleChoice.value = false;
  duration.value = '24h';
  publicResults.value = true;
  isSubmitting.value = false;
}

function open() {
  resetForm();
  dialogRef.value?.open();
}

function handleClose() {
  if (hasUnsavedChanges.value) {
    confirmDiscardRef.value?.open();
    return;
  }
  resetForm();
}

function confirmDiscard() {
  confirmDiscardRef.value?.close();
  resetForm();
  dialogRef.value?.close();
}

function handleSubmit() {
  if (!canSubmit.value) return;
  isSubmitting.value = true;

  const pollData = {
    question: question.value.trim(),
    options: options.value
      .filter(o => o.text.trim().length > 0)
      .map(o => ({ text: o.text.trim() })),
    multiple_choice: multipleChoice.value,
    public_results: publicResults.value,
    expires_at: computeExpiresAt(duration.value),
  };

  emit('submit', pollData);
  resetForm();
  isSubmitting.value = false;
  dialogRef.value?.close();
}

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('INTERNAL_CHAT.POLL.CREATE')"
    :confirm-button-label="t('INTERNAL_CHAT.POLL.CREATE')"
    :disable-confirm-button="!canSubmit"
    :is-loading="isSubmitting"
    @confirm="handleSubmit"
    @close="handleClose"
  >
    <div class="flex flex-col gap-4">
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('INTERNAL_CHAT.POLL.QUESTION') }}
        </label>
        <input
          v-model="question"
          type="text"
          class="w-full rounded-lg border border-n-slate-6 bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 placeholder-n-slate-10 outline-none focus:border-n-brand"
          :placeholder="t('INTERNAL_CHAT.POLL.QUESTION')"
        />
      </div>

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('INTERNAL_CHAT.POLL.OPTIONS') }}
        </label>
        <div class="space-y-2">
          <div
            v-for="(option, index) in options"
            :key="index"
            class="flex gap-2"
          >
            <input
              v-model="option.text"
              type="text"
              class="flex-1 rounded-lg border border-n-slate-6 bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 placeholder-n-slate-10 outline-none focus:border-n-brand"
              :placeholder="`Option ${index + 1}`"
            />
            <button
              v-if="options.length > 2"
              type="button"
              class="flex-shrink-0 flex h-[34px] w-[34px] items-center justify-center rounded-lg border border-transparent text-n-slate-11 hover:border-n-ruby-6 hover:bg-n-ruby-3 hover:text-n-ruby-11"
              @click="removeOption(index)"
            >
              <Icon icon="i-lucide-x" class="size-4" />
            </button>
          </div>
        </div>
        <button
          v-if="options.length < MAX_OPTIONS"
          type="button"
          class="mt-2 flex items-center gap-1 text-sm text-n-brand hover:opacity-80"
          @click="addOption"
        >
          <Icon icon="i-lucide-plus" class="size-3.5" />
          {{ t('INTERNAL_CHAT.POLL.ADD_OPTION') }}
        </button>
      </div>

      <label class="flex cursor-pointer items-center justify-between">
        <span class="text-sm text-n-slate-12">
          {{ t('INTERNAL_CHAT.POLL.MULTIPLE_CHOICE') }}
        </span>
        <Switch v-model="multipleChoice" />
      </label>

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('INTERNAL_CHAT.POLL.DURATION') }}
        </label>
        <NextSelect v-model="duration" :options="durationOptions" />
      </div>

      <label class="flex cursor-pointer items-center justify-between">
        <span class="text-sm text-n-slate-12">
          {{ t('INTERNAL_CHAT.POLL.PUBLIC_RESULTS') }}
        </span>
        <Switch v-model="publicResults" />
      </label>
    </div>
  </Dialog>

  <Dialog
    ref="confirmDiscardRef"
    type="alert"
    :title="t('INTERNAL_CHAT.POLL.DISCARD_TITLE')"
    :description="t('INTERNAL_CHAT.POLL.DISCARD_DESCRIPTION')"
    :confirm-button-label="t('INTERNAL_CHAT.POLL.DISCARD')"
    @confirm="confirmDiscard"
  />
</template>
