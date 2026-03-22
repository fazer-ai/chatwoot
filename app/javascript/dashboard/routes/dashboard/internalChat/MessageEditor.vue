<script setup>
import { ref, computed, watch, nextTick } from 'vue';
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
  editingMessage: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits([
  'send',
  'typing',
  'draftUpdate',
  'create-poll',
  'cancelEdit',
]);

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

function cancelEdit() {
  messageContent.value = '';
  if (textareaRef.value) textareaRef.value.style.height = 'auto';
  emit('cancelEdit');
}

function wrapSelection(marker) {
  const textarea = textareaRef.value;
  if (!textarea) return;
  const start = textarea.selectionStart;
  const end = textarea.selectionEnd;
  const text = messageContent.value;
  const selected = text.substring(start, end);
  const wrapped = `${marker}${selected}${marker}`;
  messageContent.value =
    text.substring(0, start) + wrapped + text.substring(end);
  nextTick(() => {
    textarea.focus();
    textarea.selectionStart = start + marker.length;
    textarea.selectionEnd = end + marker.length;
  });
}

watch(
  () => props.editingMessage,
  msg => {
    if (msg) {
      messageContent.value = msg.content || '';
      nextTick(() => {
        autoResize();
        textareaRef.value?.focus();
      });
    }
  },
  { immediate: true }
);

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
  if (event.key === 'Escape' && props.editingMessage) {
    cancelEdit();
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
      v-if="editingMessage"
      class="flex items-center justify-between px-3 py-1.5 text-xs text-n-brand border-b border-n-slate-5"
    >
      <span class="flex items-center gap-1">
        <Icon icon="i-lucide-pencil" class="size-3" />
        {{ t('INTERNAL_CHAT.MESSAGE.EDITING') }}
      </span>
      <button class="text-n-slate-11 hover:text-n-slate-12" @click="cancelEdit">
        <Icon icon="i-lucide-x" class="size-3.5" />
      </button>
    </div>
    <div
      class="flex items-end gap-2 rounded-lg border border-n-slate-6 bg-n-solid-1 px-3 py-2"
    >
      <div class="flex-1">
        <div class="flex items-center gap-0.5 px-1 pb-1">
          <button
            type="button"
            class="flex items-center justify-center rounded p-1 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
            :title="t('INTERNAL_CHAT.MESSAGE.BOLD')"
            @click="wrapSelection('**')"
          >
            <Icon icon="i-lucide-bold" class="size-3.5" />
          </button>
          <button
            type="button"
            class="flex items-center justify-center rounded p-1 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
            :title="t('INTERNAL_CHAT.MESSAGE.ITALIC')"
            @click="wrapSelection('*')"
          >
            <Icon icon="i-lucide-italic" class="size-3.5" />
          </button>
          <button
            type="button"
            class="flex items-center justify-center rounded p-1 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
            :title="t('INTERNAL_CHAT.MESSAGE.CODE')"
            @click="wrapSelection('`')"
          >
            <Icon icon="i-lucide-code" class="size-3.5" />
          </button>
        </div>
        <textarea
          ref="textareaRef"
          v-model="messageContent"
          :placeholder="placeholder || t('INTERNAL_CHAT.MESSAGE.PLACEHOLDER')"
          :disabled="disabled"
          rows="1"
          class="w-full resize-none bg-transparent text-sm text-n-slate-12 placeholder-n-slate-10 outline-none"
          @keydown="handleKeyDown"
          @input="handleInput"
        />
      </div>
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
