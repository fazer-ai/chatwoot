<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';

import NextButton from 'dashboard/components-next/button/Button.vue';

const emit = defineEmits(['close', 'setAiStatus']);

const { t } = useI18n();

const selected = ref(null);

const hasSelection = computed(() => selected.value !== null);

const onClose = () => emit('close');

const handleSubmit = () => {
  if (!hasSelection.value) return;
  emit('setAiStatus', selected.value);
};
</script>

<template>
  <!-- Click-outside is handled by the parent wrapper (which also owns the
       trigger button) so a click on the button doesn't trip an "outside"
       detector attached here — otherwise the popover closes and the button
       immediately re-opens it in the same event tick and the Apply click
       never lands. -->
  <div
    class="absolute ltr:right-2 rtl:left-2 top-12 origin-top-right z-20 w-60 bg-n-alpha-3 backdrop-blur-[100px] border-n-weak rounded-lg border border-solid shadow-md"
    role="dialog"
    aria-labelledby="ai-status-dialog-title"
  >
    <div class="triangle">
      <svg height="12" viewBox="0 0 24 12" width="24">
        <path d="M20 12l-8-8-12 12" fill-rule="evenodd" stroke-width="1px" />
      </svg>
    </div>
    <div class="flex items-center justify-between p-2.5">
      <span id="ai-status-dialog-title" class="text-sm font-medium">
        {{ t('BULK_ACTION.AI_STATUS.TITLE') }}
      </span>
      <NextButton ghost xs slate icon="i-lucide-x" @click="onClose" />
    </div>
    <div class="flex flex-col">
      <ul
        class="m-0 list-none p-0"
        role="radiogroup"
        :aria-label="t('BULK_ACTION.AI_STATUS.TITLE')"
      >
        <li class="my-1 mx-0 py-0 px-2.5">
          <label
            class="items-center rounded-md cursor-pointer flex gap-2 py-1.5 px-2.5 hover:bg-n-slate-3 dark:hover:bg-n-solid-3 has-[:checked]:bg-n-slate-2"
          >
            <input
              v-model="selected"
              type="radio"
              name="ai-status-bulk"
              :value="true"
              class="m-0"
              :aria-label="t('BULK_ACTION.AI_STATUS.ENABLE')"
            />
            <span
              class="inline-flex items-center gap-1 h-4 px-1.5 py-0.5 rounded-[4px] text-xs font-medium leading-tight bg-n-teal-9 text-white"
            >
              <span class="inline-block w-2 h-2 rounded-sm bg-white" />
              {{ t('CONVERSATION.AI_STATUS.LABEL') }}
            </span>
            <span class="text-sm">{{ t('BULK_ACTION.AI_STATUS.ENABLE') }}</span>
          </label>
        </li>
        <li class="my-1 mx-0 py-0 px-2.5">
          <label
            class="items-center rounded-md cursor-pointer flex gap-2 py-1.5 px-2.5 hover:bg-n-slate-3 dark:hover:bg-n-solid-3 has-[:checked]:bg-n-slate-2"
          >
            <input
              v-model="selected"
              type="radio"
              name="ai-status-bulk"
              :value="false"
              class="m-0"
              :aria-label="t('BULK_ACTION.AI_STATUS.DISABLE')"
            />
            <span
              class="inline-flex items-center gap-1 h-4 px-1.5 py-0.5 rounded-[4px] text-xs font-medium leading-tight bg-n-ruby-9 text-white"
            >
              <span class="inline-block w-2 h-2 rounded-sm bg-white" />
              {{ t('CONVERSATION.AI_STATUS.LABEL') }}
            </span>
            <span class="text-sm">{{
              t('BULK_ACTION.AI_STATUS.DISABLE')
            }}</span>
          </label>
        </li>
      </ul>
      <footer class="p-2">
        <NextButton
          sm
          type="submit"
          class="w-full"
          :label="t('BULK_ACTION.AI_STATUS.APPLY')"
          :disabled="!hasSelection"
          @click="handleSubmit"
        />
      </footer>
    </div>
  </div>
</template>

<style scoped lang="scss">
.triangle {
  @apply block z-10 absolute text-left -top-3 ltr:right-[--triangle-position] rtl:left-[--triangle-position];

  svg path {
    @apply fill-n-alpha-3 backdrop-blur-[100px] stroke-n-weak;
  }
}
</style>
