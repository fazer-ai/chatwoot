<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  disabled: {
    type: Boolean,
    default: false,
  },
  placeholder: {
    type: String,
    default: '',
  },
  initialContent: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['send', 'typing', 'draftUpdate', 'create-poll']);

const { t } = useI18n();

const messageContent = ref(props.initialContent);

let draftTimer = null;
const textareaRef = ref(null);

const canSend = computed(() => {
  return messageContent.value.trim().length > 0 && !props.disabled;
});

function autoResize() {
  const textarea = textareaRef.value;
  if (!textarea) return;
  textarea.style.height = 'auto';
  textarea.style.height = `${Math.min(textarea.scrollHeight, 160)}px`;
}

function handleSend() {
  if (!canSend.value) return;
  emit('send', messageContent.value.trim());
  messageContent.value = '';
  if (draftTimer) {
    clearTimeout(draftTimer);
    draftTimer = null;
  }
  emit('draftUpdate', '');
  if (textareaRef.value) {
    textareaRef.value.style.height = 'auto';
  }
}

function handleKeyDown(event) {
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault();
    handleSend();
  }
}

function handleInput() {
  emit('typing');
  autoResize();
  if (draftTimer) {
    clearTimeout(draftTimer);
  }
  draftTimer = setTimeout(() => {
    emit('draftUpdate', messageContent.value);
  }, 3000);
}

function focus() {
  textareaRef.value?.focus();
}

function setContent(content) {
  messageContent.value = content;
  autoResize();
}

defineExpose({ focus, setContent });
</script>

<template>
  <div class="border-t border-n-slate-5 bg-n-solid-2 px-4 py-3">
    <div
      class="flex items-end gap-2 rounded-lg border border-n-slate-6 bg-n-solid-1 px-3 py-2"
    >
      <textarea
        ref="textareaRef"
        v-model="messageContent"
        :placeholder="placeholder || t('INTERNAL_CHAT.MESSAGE.PLACEHOLDER')"
        :disabled="disabled"
        rows="1"
        class="flex-1 resize-none bg-transparent text-sm text-n-slate-12 placeholder-n-slate-10 outline-none"
        @keydown="handleKeyDown"
        @input="handleInput"
      />
      <button
        class="flex-shrink-0 flex items-center justify-center rounded-lg p-1.5 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 transition-colors"
        :disabled="disabled"
        :title="t('INTERNAL_CHAT.POLL.CREATE')"
        @click="emit('create-poll')"
      >
        <Icon icon="i-lucide-bar-chart-2" class="size-4" />
      </button>
      <button
        class="flex-shrink-0 flex items-center justify-center rounded-lg p-1.5 transition-colors"
        :class="
          canSend
            ? 'bg-n-brand text-white hover:opacity-90'
            : 'text-n-slate-9 cursor-not-allowed'
        "
        :disabled="!canSend"
        :title="t('INTERNAL_CHAT.MESSAGE.SEND')"
        @click="handleSend"
      >
        <Icon icon="i-lucide-send-horizontal" class="size-4" />
      </button>
    </div>
  </div>
</template>
