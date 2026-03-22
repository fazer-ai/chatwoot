<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import WootWriter from 'dashboard/components/widgets/WootWriter/Editor.vue';

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

const editorContent = ref(props.initialContent);

let draftTimer = null;

const canSend = computed(() => {
  return editorContent.value.trim().length > 0 && !props.disabled;
});

function cancelEdit() {
  editorContent.value = '';
  emit('cancelEdit');
}

watch(
  () => props.editingMessage,
  msg => {
    if (msg) {
      editorContent.value = msg.content || '';
    }
  },
  { immediate: true }
);

watch(editorContent, newContent => {
  if (draftTimer) clearTimeout(draftTimer);
  draftTimer = setTimeout(() => {
    emit('draftUpdate', newContent);
  }, 3000);
});

function handleSend() {
  if (!canSend.value) return;
  emit('send', editorContent.value.trim());
  editorContent.value = '';
  if (draftTimer) {
    clearTimeout(draftTimer);
    draftTimer = null;
  }
  emit('draftUpdate', '');
}

function handleKeyDown(event) {
  if (
    (event.metaKey || event.ctrlKey) &&
    event.key === 'Enter' &&
    !event.isComposing
  ) {
    event.preventDefault();
    handleSend();
  }
  if (event.key === 'Escape' && props.editingMessage) {
    cancelEdit();
  }
}

function handleTypingOn() {
  emit('typing');
}

function focus() {
  // WootWriter focuses on mount by default
}

function setContent(content) {
  editorContent.value = content;
}

onBeforeUnmount(() => {
  if (draftTimer) {
    clearTimeout(draftTimer);
    draftTimer = null;
  }
});

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
      @keydown="handleKeyDown"
    >
      <div class="flex-1 min-w-0">
        <WootWriter
          v-model:model-value="editorContent"
          channel-type="Context::Default"
          :placeholder="placeholder || t('INTERNAL_CHAT.MESSAGE.PLACEHOLDER')"
          :disabled="disabled"
          :enable-suggestions="false"
          :enable-variables="false"
          :enable-canned-responses="false"
          :enable-captain-tools="false"
          :enable-copilot="false"
          :allow-signature="false"
          focus-on-mount
          @typing-on="handleTypingOn"
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
