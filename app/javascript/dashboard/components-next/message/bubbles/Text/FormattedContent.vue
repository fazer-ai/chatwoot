<script setup>
import { computed } from 'vue';
import { useMessageContext } from '../../provider.js';

import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { MESSAGE_VARIANTS } from '../../constants';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  content: {
    type: String,
    required: true,
  },
});

const { variant, contentAttributes, shouldGroupWithNext } = useMessageContext();

const formattedContent = computed(() => {
  if (variant.value === MESSAGE_VARIANTS.ACTIVITY) {
    return props.content;
  }

  return new MessageFormatter(props.content).formattedMessage;
});

// Show edited indicator inline when meta is hidden (grouped messages)
const isEdited = computed(() => {
  return contentAttributes.value?.isEdited === true;
});

const previousContent = computed(() => {
  return contentAttributes.value?.previousContent || '';
});

const shouldShowEditedIndicator = computed(() => {
  return isEdited.value && shouldGroupWithNext.value;
});

const iconColorClass = computed(() => {
  return variant.value === MESSAGE_VARIANTS.PRIVATE
    ? 'text-n-amber-12/50'
    : 'text-n-slate-11';
});
</script>

<template>
  <span class="inline">
    <span v-dompurify-html="formattedContent" class="prose prose-bubble" />
    <span
      v-if="shouldShowEditedIndicator"
      v-tooltip.top="{
        content: previousContent,
        delay: { show: 300, hide: 0 },
      }"
      :class="iconColorClass"
      class="inline-flex items-center ml-1 align-middle cursor-help"
    >
      <Icon icon="i-lucide-pencil" class="size-3" />
    </span>
  </span>
</template>
