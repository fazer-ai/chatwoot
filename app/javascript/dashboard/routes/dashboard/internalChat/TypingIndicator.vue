<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  typingUsers: {
    type: Array,
    default: () => [],
  },
});

const { t } = useI18n();

const typingText = computed(() => {
  if (props.typingUsers.length === 0) return '';
  if (props.typingUsers.length === 1) {
    return t('INTERNAL_CHAT.TYPING.SINGLE', {
      name: props.typingUsers[0].name,
    });
  }
  const names = props.typingUsers.map(u => u.name).join(', ');
  return t('INTERNAL_CHAT.TYPING.MULTIPLE', { names });
});
</script>

<template>
  <div
    v-show="typingUsers.length > 0"
    class="flex items-center gap-2 px-4 py-1 text-xs text-n-slate-11"
  >
    <div class="flex items-center gap-0.5">
      <span
        class="inline-block size-1.5 rounded-full bg-n-slate-9 animate-bounce [animation-delay:0ms]"
      />
      <span
        class="inline-block size-1.5 rounded-full bg-n-slate-9 animate-bounce [animation-delay:150ms]"
      />
      <span
        class="inline-block size-1.5 rounded-full bg-n-slate-9 animate-bounce [animation-delay:300ms]"
      />
    </div>
    <span>{{ typingText }}</span>
  </div>
</template>
