<script>
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { messageStamp } from 'shared/helpers/timeHelper';

export default {
  name: 'UserMessageBubble',
  props: {
    message: {
      type: String,
      default: '',
    },
    status: {
      type: String,
      default: 'sent',
    },
    createdAt: {
      type: [String, Number],
      default: '',
    },
    isRead: {
      type: Boolean,
      default: false,
    },
  },
  setup() {
    const { formatMessage } = useMessageFormatter();
    return { formatMessage };
  },
  computed: {
    readableTime() {
      return this.createdAt ? messageStamp(this.createdAt) : '';
    },
    tickIcon() {
      // WhatsApp tick semantics: in_progress -> clock; failed -> handled by
      // the parent component (red retry chip); sent/delivered -> double
      // check grey; read -> double check blue.
      if (this.status === 'in_progress' || this.status === 'progress') {
        return 'clock';
      }
      if (this.status === 'failed') {
        return null;
      }
      return this.isRead ? 'read' : 'sent';
    },
  },
};
</script>

<template>
  <div class="chat-bubble user">
    <span
      v-dompurify-html="formatMessage(message, false)"
      class="message-content"
    />
    <span class="message-meta">
      <span>{{ readableTime }}</span>
      <span v-if="tickIcon === 'clock'" class="ticks" aria-hidden="true">
        <svg viewBox="0 0 16 16" width="14" height="14" fill="currentColor">
          <path
            d="M8 1.5a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13Zm0 12A5.5 5.5 0 1 1 8 2.5a5.5 5.5 0 0 1 0 11Zm.5-5.79V4a.5.5 0 0 0-1 0v4a.5.5 0 0 0 .15.35l2.5 2.5a.5.5 0 1 0 .7-.7L8.5 7.71Z"
          />
        </svg>
      </span>
      <span
        v-else-if="tickIcon"
        class="ticks"
        :class="{ 'ticks-read': tickIcon === 'read' }"
        aria-hidden="true"
      >
        <svg viewBox="0 0 16 11" width="16" height="11" fill="currentColor">
          <path
            d="M11.071.653a.5.5 0 0 1 .017.704l-6.5 7a.5.5 0 0 1-.717.017L.293 4.96a.5.5 0 1 1 .707-.707l3.227 3.227 6.14-6.61a.5.5 0 0 1 .704-.017Z"
          />
          <path
            d="M15.071.653a.5.5 0 0 1 .017.704l-6.5 7a.5.5 0 0 1-.717.017l-.97-.97a.5.5 0 0 1 .708-.707l.609.61L14.367.636a.5.5 0 0 1 .704.017Z"
          />
        </svg>
      </span>
    </span>
  </div>
</template>

<style lang="scss" scoped>
.chat-bubble.user {
  :deep(p) {
    display: inline;
  }

  :deep(p code) {
    @apply bg-n-alpha-2 text-n-slate-12 px-1 rounded-sm;
  }

  :deep(pre) {
    @apply bg-n-alpha-2 text-n-slate-12 p-2 rounded;

    code {
      @apply bg-transparent text-n-slate-12;
    }
  }

  :deep(blockquote) {
    @apply bg-transparent ltr:border-l-2 rtl:border-r-2 border-solid pl-2;
    border-color: #6b9d65;
  }
}
</style>
