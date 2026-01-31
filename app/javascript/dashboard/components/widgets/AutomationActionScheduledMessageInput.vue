<script setup>
import { computed } from 'vue';

import AutomationActionFileInput from './AutomationFileInput.vue';
import WootMessageEditor from 'dashboard/components/widgets/WootWriter/Editor.vue';

const props = defineProps({
  modelValue: {
    type: [Object, Array],
    default: () => ({}),
  },
  initialFileName: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['update:modelValue']);

const normalizedParams = computed(() => {
  const value = props.modelValue;
  if (Array.isArray(value)) {
    const first = value[0];
    return typeof first === 'object' && first !== null ? first : {};
  }
  return typeof value === 'object' && value !== null ? value : {};
});

const updateParams = updates => {
  const newParams = { ...normalizedParams.value, ...updates };
  emit('update:modelValue', [newParams]);
};

const content = computed({
  get: () => {
    const value = normalizedParams.value.content;
    return typeof value === 'string' ? value : '';
  },
  set: value => updateParams({ content: value }),
});

const delayMinutes = computed({
  get: () => normalizedParams.value.delay_minutes ?? '',
  set: value => {
    const numValue = Math.min(Math.max(1, Number(value) || 1), 999999);
    updateParams({ delay_minutes: numValue });
  },
});

const attachmentBlobIds = computed({
  get: () => {
    const blobId = normalizedParams.value.blob_id;
    return blobId ? [blobId] : [];
  },
  set: value => {
    const blobId = Array.isArray(value) ? value[0] : value;
    updateParams({ blob_id: blobId });
  },
});
</script>

<template>
  <div class="mt-2 flex flex-col gap-1">
    <div class="flex flex-col gap-1">
      <label class="text-xs text-n-slate-11">
        {{ $t('AUTOMATION.ACTION.SCHEDULED_MESSAGE_DELAY_LABEL') }}
      </label>
      <input
        v-model="delayMinutes"
        type="number"
        min="1"
        max="999999"
        class="answer--text-input !mb-0"
        :placeholder="
          $t('AUTOMATION.ACTION.SCHEDULED_MESSAGE_DELAY_PLACEHOLDER')
        "
      />
    </div>

    <WootMessageEditor
      v-model="content"
      rows="4"
      enable-variables
      :placeholder="$t('AUTOMATION.ACTION.TEAM_MESSAGE_INPUT_PLACEHOLDER')"
      class="action-message"
    />

    <AutomationActionFileInput
      v-model="attachmentBlobIds"
      :initial-file-name="initialFileName"
    />
  </div>
</template>
