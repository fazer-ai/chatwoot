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
  showPoll: {
    type: Boolean,
    default: true,
  },
  showAlsoSendInChannel: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'send',
  'typing',
  'draftUpdate',
  'create-poll',
  'cancelEdit',
]);

const alsoSendInChannel = ref(false);

const { t } = useI18n();

const editorRef = ref(null);
const fileInputRef = ref(null);
const editorContent = ref(props.initialContent);
const attachedFiles = ref([]);

let draftTimer = null;

const canSend = computed(() => {
  return (
    (editorContent.value.trim().length > 0 || attachedFiles.value.length > 0) &&
    !props.disabled
  );
});

function cancelEdit() {
  editorContent.value = '';
  attachedFiles.value = [];
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

function focusEditor() {
  editorRef.value?.$el?.querySelector('.ProseMirror')?.focus();
}

function handleSend() {
  if (!canSend.value) return;
  const content = editorContent.value.trim();
  const files = [...attachedFiles.value];
  editorContent.value = '';
  attachedFiles.value = [];
  if (draftTimer) {
    clearTimeout(draftTimer);
    draftTimer = null;
  }
  emit('draftUpdate', '');
  emit('send', content, {
    alsoSendInChannel: alsoSendInChannel.value,
    files,
  });
  setTimeout(() => focusEditor(), 200);
}

function handleKeyDown(event) {
  if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) {
    event.preventDefault();
    event.stopPropagation();
    handleSend();
    return;
  }
  if (event.key === 'Escape' && props.editingMessage) {
    cancelEdit();
  }
}

function handleTypingOn() {
  emit('typing');
}

function openFilePicker() {
  fileInputRef.value?.click();
}

function handleFileChange(event) {
  const files = Array.from(event.target.files || []);
  attachedFiles.value = [...attachedFiles.value, ...files];
  if (fileInputRef.value) fileInputRef.value.value = '';
}

function removeFile(index) {
  attachedFiles.value.splice(index, 1);
}

function filePreviewUrl(file) {
  return URL.createObjectURL(file);
}

function focus() {
  focusEditor();
}

function setContent(content) {
  editorContent.value = content;
}

function getContent() {
  return editorContent.value;
}

onBeforeUnmount(() => {
  if (draftTimer) {
    clearTimeout(draftTimer);
    draftTimer = null;
  }
});

defineExpose({ focus, setContent, getContent });
</script>

<template>
  <div class="border-t border-n-slate-5 bg-n-solid-2 px-4 py-3">
    <div
      v-if="editingMessage"
      class="flex items-center justify-between border-b border-n-slate-5 px-3 py-1.5 text-xs text-n-brand"
    >
      <span class="flex items-center gap-1">
        <Icon icon="i-lucide-pencil" class="size-3" />
        {{ t('INTERNAL_CHAT.MESSAGE.EDITING') }}
      </span>
      <button class="text-n-slate-11 hover:text-n-slate-12" @click="cancelEdit">
        <Icon icon="i-lucide-x" class="size-3.5" />
      </button>
    </div>
    <label
      v-if="showAlsoSendInChannel"
      class="flex cursor-pointer items-center gap-1.5 px-1 pb-1 text-xs text-n-slate-10"
    >
      <input
        v-model="alsoSendInChannel"
        type="checkbox"
        class="rounded border-n-slate-6"
      />
      {{ t('INTERNAL_CHAT.THREAD.ALSO_SEND_IN_CHANNEL') }}
    </label>
    <!-- Attached files preview -->
    <div v-if="attachedFiles.length" class="mb-1 flex flex-wrap gap-2 px-1">
      <div
        v-for="(file, index) in attachedFiles"
        :key="index"
        class="group relative"
      >
        <img
          v-if="file.type?.startsWith('image/')"
          :src="filePreviewUrl(file)"
          class="h-16 w-16 rounded-lg border border-n-slate-6 object-cover"
        />
        <div
          v-else
          class="flex h-16 items-center gap-1 rounded-lg border border-n-slate-6 bg-n-alpha-1 px-3"
        >
          <Icon icon="i-lucide-file" class="size-4 text-n-slate-10" />
          <span class="max-w-24 truncate text-xs text-n-slate-12">
            {{ file.name }}
          </span>
        </div>
        <button
          type="button"
          class="absolute -right-1 -top-1 flex size-4 items-center justify-center rounded-full bg-n-slate-12 text-white hover:bg-n-ruby-9"
          @click="removeFile(index)"
        >
          <Icon icon="i-lucide-x" class="size-2.5" />
        </button>
      </div>
    </div>
    <div
      class="flex items-end gap-2 rounded-lg border border-n-slate-6 bg-n-solid-1 px-3 py-2"
      @keydown.capture="handleKeyDown"
    >
      <div class="flex-1 min-w-0">
        <WootWriter
          ref="editorRef"
          v-model:model-value="editorContent"
          channel-type="Context::Default"
          :placeholder="placeholder || t('INTERNAL_CHAT.MESSAGE.PLACEHOLDER')"
          enable-suggestions
          :enable-variables="false"
          :enable-canned-responses="false"
          :enable-captain-tools="false"
          :enable-copilot="false"
          :allow-signature="false"
          focus-on-mount
          @typing-on="handleTypingOn"
        />
      </div>
      <input
        ref="fileInputRef"
        type="file"
        multiple
        class="hidden"
        @change="handleFileChange"
      />
      <button
        type="button"
        class="flex-shrink-0 flex items-center justify-center rounded-lg p-1.5 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 transition-colors"
        :title="t('INTERNAL_CHAT.MESSAGE.UPLOAD_FILE')"
        @click="openFilePicker"
      >
        <Icon icon="i-lucide-paperclip" class="size-4" />
      </button>
      <button
        v-if="showPoll"
        type="button"
        class="flex-shrink-0 flex items-center justify-center rounded-lg p-1.5 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 transition-colors"
        :title="t('INTERNAL_CHAT.POLL.CREATE')"
        @click="emit('create-poll')"
      >
        <Icon icon="i-lucide-bar-chart-2" class="size-4" />
      </button>
      <button
        type="button"
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
