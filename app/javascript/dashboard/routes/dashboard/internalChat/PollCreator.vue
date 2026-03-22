<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const emit = defineEmits(['submit', 'close']);

const { t } = useI18n();

const question = ref('');
const options = ref([{ text: '' }, { text: '' }]);
const multipleChoice = ref(false);
const duration = ref('24h');
const publicResults = ref(true);
const isSubmitting = ref(false);

const DURATION_OPTIONS = [
  { value: '24h', label: '24 hours' },
  { value: '7d', label: '7 days' },
  { value: '14d', label: '14 days' },
  { value: '30d', label: '30 days' },
];

const MAX_OPTIONS = 10;

const canSubmit = computed(() => {
  const filledOptions = options.value.filter(o => o.text.trim().length > 0);
  return (
    question.value.trim().length > 0 &&
    filledOptions.length >= 2 &&
    !isSubmitting.value
  );
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
  setTimeout(() => {
    isSubmitting.value = false;
  }, 1000);
}
</script>

<template>
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
    <div
      class="mx-4 w-full max-w-lg rounded-xl border border-n-slate-5 bg-n-solid-1 shadow-xl"
    >
      <div
        class="flex items-center justify-between border-b border-n-slate-5 px-5 py-4"
      >
        <h3 class="text-base font-semibold text-n-slate-12">
          {{ t('INTERNAL_CHAT.POLL.CREATE') }}
        </h3>
        <button
          class="flex items-center justify-center rounded p-1 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          @click="emit('close')"
        >
          <Icon icon="i-lucide-x" class="size-4" />
        </button>
      </div>

      <div class="max-h-[70vh] space-y-4 overflow-y-auto px-5 py-4">
        <div>
          <label class="mb-1 block text-sm font-medium text-n-slate-12">
            {{ t('INTERNAL_CHAT.POLL.QUESTION') }}
          </label>
          <input
            v-model="question"
            type="text"
            class="w-full rounded-lg border border-n-slate-6 bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 placeholder-n-slate-10 outline-none focus:border-n-brand"
            :placeholder="t('INTERNAL_CHAT.POLL.QUESTION')"
          />
        </div>

        <div>
          <label class="mb-1 block text-sm font-medium text-n-slate-12">
            {{ t('INTERNAL_CHAT.POLL.OPTIONS') }}
          </label>
          <div class="space-y-2">
            <div
              v-for="(option, index) in options"
              :key="index"
              class="flex items-center gap-2"
            >
              <input
                v-model="option.text"
                type="text"
                class="flex-1 rounded-lg border border-n-slate-6 bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 placeholder-n-slate-10 outline-none focus:border-n-brand"
                :placeholder="`Option ${index + 1}`"
              />
              <button
                v-if="options.length > 2"
                class="flex items-center justify-center rounded p-1 text-n-slate-11 hover:bg-n-ruby-3 hover:text-n-ruby-11"
                @click="removeOption(index)"
              >
                <Icon icon="i-lucide-x" class="size-4" />
              </button>
            </div>
          </div>
          <button
            v-if="options.length < MAX_OPTIONS"
            class="mt-2 flex items-center gap-1 text-sm text-n-brand hover:opacity-80"
            @click="addOption"
          >
            <Icon icon="i-lucide-plus" class="size-3.5" />
            {{ t('INTERNAL_CHAT.POLL.ADD_OPTION') }}
          </button>
        </div>

        <div class="flex items-center justify-between">
          <label class="text-sm text-n-slate-12">
            {{ t('INTERNAL_CHAT.POLL.MULTIPLE_CHOICE') }}
          </label>
          <button
            class="relative h-5 w-9 rounded-full transition-colors"
            :class="multipleChoice ? 'bg-n-brand' : 'bg-n-slate-7'"
            @click="multipleChoice = !multipleChoice"
          >
            <span
              class="absolute top-0.5 left-0.5 size-4 rounded-full bg-white transition-transform"
              :class="{ 'translate-x-4': multipleChoice }"
            />
          </button>
        </div>

        <div>
          <label class="mb-1 block text-sm font-medium text-n-slate-12">
            {{ t('INTERNAL_CHAT.POLL.DURATION') }}
          </label>
          <select
            v-model="duration"
            class="w-full rounded-lg border border-n-slate-6 bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand"
          >
            <option
              v-for="opt in DURATION_OPTIONS"
              :key="opt.value"
              :value="opt.value"
            >
              {{ opt.label }}
            </option>
          </select>
        </div>

        <div class="flex items-center justify-between">
          <label class="text-sm text-n-slate-12">
            {{ t('INTERNAL_CHAT.POLL.PUBLIC_RESULTS') }}
          </label>
          <button
            class="relative h-5 w-9 rounded-full transition-colors"
            :class="publicResults ? 'bg-n-brand' : 'bg-n-slate-7'"
            @click="publicResults = !publicResults"
          >
            <span
              class="absolute top-0.5 left-0.5 size-4 rounded-full bg-white transition-transform"
              :class="{ 'translate-x-4': publicResults }"
            />
          </button>
        </div>
      </div>

      <div
        class="flex items-center justify-end gap-2 border-t border-n-slate-5 px-5 py-4"
      >
        <button
          class="rounded-lg px-4 py-2 text-sm text-n-slate-11 hover:bg-n-alpha-2"
          @click="emit('close')"
        >
          {{ t('INTERNAL_CHAT.POLL.CANCEL') }}
        </button>
        <button
          class="rounded-lg px-4 py-2 text-sm font-medium transition-colors"
          :class="
            canSubmit
              ? 'bg-n-brand text-white hover:opacity-90'
              : 'bg-n-slate-4 text-n-slate-9 cursor-not-allowed'
          "
          :disabled="!canSubmit"
          @click="handleSubmit"
        >
          {{ t('INTERNAL_CHAT.POLL.CREATE') }}
        </button>
      </div>
    </div>
  </div>
</template>
