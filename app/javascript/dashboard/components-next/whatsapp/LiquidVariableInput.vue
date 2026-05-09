<script setup>
import { computed, ref } from 'vue';
import { onClickOutside } from '@vueuse/core';
import { MESSAGE_VARIABLES } from 'shared/constants/messages';
import Input from 'dashboard/components-next/input/Input.vue';

const props = defineProps({
  modelValue: { type: String, default: '' },
  placeholder: { type: String, default: '' },
  type: { type: String, default: 'text' },
});
const emit = defineEmits(['update:modelValue']);

// Surface only the tokens that make sense outside an ongoing conversation.
// In a campaign there is no `conversation.id` yet (the conversation is built
// per recipient by the dispatcher) and there's no editing agent reading
// `agent.email`, so we filter those out to avoid suggesting tokens that
// would render empty.
const ALLOWED_KEYS = new Set([
  'contact.id',
  'contact.name',
  'contact.first_name',
  'contact.last_name',
  'contact.email',
  'contact.phone',
  'agent.name',
  'agent.first_name',
  'agent.last_name',
  'agent.email',
  'inbox.name',
]);

const variables = computed(() =>
  MESSAGE_VARIABLES.filter(v => ALLOWED_KEYS.has(v.key))
);

const inputRef = ref(null);
const wrapperRef = ref(null);
const showSuggestions = ref(false);

onClickOutside(wrapperRef, () => {
  showSuggestions.value = false;
});

const onUpdate = value => {
  emit('update:modelValue', value);
  // Trigger the variable picker right after the user types `{{`.
  showSuggestions.value = typeof value === 'string' && value.endsWith('{{');
};

const tokenPreview = key => `{{${key}}}`;

const insertVariable = variable => {
  const current = props.modelValue || '';
  // Replace the trailing `{{` (if any) with the full token; otherwise append.
  const next = current.endsWith('{{')
    ? `${current.slice(0, -2)}{{${variable.key}}}`
    : `${current}{{${variable.key}}}`;
  emit('update:modelValue', next);
  showSuggestions.value = false;
};
</script>

<template>
  <div ref="wrapperRef" class="relative">
    <Input
      ref="inputRef"
      :model-value="modelValue"
      :type="type"
      :placeholder="placeholder"
      class="flex-1"
      @update:model-value="onUpdate"
      @focus="showSuggestions = false"
    />
    <ul
      v-if="showSuggestions"
      class="absolute z-10 left-0 right-0 mt-1 max-h-64 overflow-y-auto rounded-lg border border-n-weak bg-n-surface-1 shadow-lg p-1"
    >
      <li
        v-for="variable in variables"
        :key="variable.key"
        class="flex flex-col items-start gap-0.5 px-3 py-2 rounded-md cursor-pointer hover:bg-n-alpha-2"
        @mousedown.prevent="insertVariable(variable)"
      >
        <span class="text-sm text-n-slate-12">{{ variable.label }}</span>
        <span class="text-xs text-n-slate-11 font-mono">
          {{ tokenPreview(variable.key) }}
        </span>
      </li>
    </ul>
  </div>
</template>
