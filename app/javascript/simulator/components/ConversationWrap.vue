<script>
import ChatMessage from 'simulator/components/ChatMessage.vue';
import AgentTypingBubble from 'simulator/components/AgentTypingBubble.vue';
import DateSeparator from 'simulator/components/DateSeparator.vue';
import Spinner from 'shared/components/Spinner.vue';
import { useDarkMode } from 'simulator/composables/useDarkMode';
import { MESSAGE_TYPE } from 'shared/constants/messages';
import { mapActions, mapGetters } from 'vuex';

export default {
  name: 'ConversationWrap',
  components: {
    ChatMessage,
    AgentTypingBubble,
    DateSeparator,
    Spinner,
  },
  props: {
    groupedMessages: {
      type: Array,
      default: () => [],
    },
  },
  setup() {
    const { darkMode } = useDarkMode();
    return { darkMode };
  },
  data() {
    return {
      previousScrollHeight: 0,
      previousConversationSize: 0,
    };
  },
  computed: {
    ...mapGetters({
      earliestMessage: 'conversation/getEarliestMessage',
      lastMessage: 'conversation/getLastMessage',
      allMessagesLoaded: 'conversation/getAllMessagesLoaded',
      isFetchingList: 'conversation/getIsFetchingList',
      conversationSize: 'conversation/getConversationSize',
      isAgentTyping: 'conversation/getIsAgentTyping',
      conversationAttributes: 'conversationAttributes/getConversationParams',
    }),
    colorSchemeClass() {
      return `${this.darkMode === 'dark' ? 'dark-scheme' : 'light-scheme'}`;
    },
    showStatusIndicator() {
      const { status } = this.conversationAttributes;
      const isConversationInPendingStatus = status === 'pending';
      const isLastMessageIncoming =
        this.lastMessage.message_type === MESSAGE_TYPE.INCOMING;
      return (
        this.isAgentTyping ||
        (isConversationInPendingStatus && isLastMessageIncoming)
      );
    },
  },
  watch: {
    allMessagesLoaded() {
      this.previousScrollHeight = 0;
    },
  },
  mounted() {
    this.$el.addEventListener('scroll', this.handleScroll);
    this.scrollToBottom();
  },
  updated() {
    if (this.previousConversationSize !== this.conversationSize) {
      this.previousConversationSize = this.conversationSize;
      this.scrollToBottom();
    }
  },
  unmounted() {
    this.$el.removeEventListener('scroll', this.handleScroll);
  },
  methods: {
    ...mapActions('conversation', ['fetchOldConversations']),
    scrollToBottom() {
      const container = this.$el;
      container.scrollTop = container.scrollHeight - this.previousScrollHeight;
      this.previousScrollHeight = 0;
    },
    handleScroll() {
      if (
        this.isFetchingList ||
        this.allMessagesLoaded ||
        !this.conversationSize
      ) {
        return;
      }

      if (this.$el.scrollTop < 100) {
        this.fetchOldConversations({ before: this.earliestMessage.id });
        this.previousScrollHeight = this.$el.scrollHeight;
      }
    },
  },
};
</script>

<template>
  <div class="conversation--container" :class="colorSchemeClass">
    <div class="conversation-wrap" :class="{ 'is-typing': isAgentTyping }">
      <div v-if="isFetchingList" class="message--loader">
        <Spinner />
      </div>
      <div
        v-for="groupedMessage in groupedMessages"
        :key="groupedMessage.date"
        class="messages-wrap"
      >
        <DateSeparator :date="groupedMessage.date" />
        <ChatMessage
          v-for="message in groupedMessage.messages"
          :key="message.id"
          :message="message"
        />
      </div>
      <AgentTypingBubble v-if="showStatusIndicator" />
    </div>
  </div>
</template>

<style scoped lang="scss">
// WhatsApp Web's chat background -- soft beige with a subtle repeating
// scribble/doodle overlay. The doodle is a small SVG data URI (paths
// stylised after the canonical WhatsApp doodle) tiled across the
// scroll area; opacity is dialled down so the bubbles still pop.
$wa-bg-light: #efeae2;
$wa-bg-dark: #0b141a;
$wa-doodle: url("data:image/svg+xml;utf8,%3Csvg xmlns='http://www.w3.org/2000/svg' width='280' height='280' viewBox='0 0 280 280' fill='none' stroke='%23262a30' stroke-opacity='0.06' stroke-width='1.5'%3E%3Cpath d='M20 40 q15 -15 30 0 t30 0'/%3E%3Ccircle cx='110' cy='35' r='6'/%3E%3Cpath d='M150 30 l8 16 -16 0 z'/%3E%3Cpath d='M200 50 q15 -20 30 0'/%3E%3Cpath d='M30 110 q20 -10 40 0 t40 0'/%3E%3Cpath d='M130 100 l6 -10 6 10 -6 10 z'/%3E%3Ccircle cx='190' cy='115' r='5'/%3E%3Cpath d='M220 105 q10 15 20 0'/%3E%3Cpath d='M50 180 q20 15 40 0 t40 0'/%3E%3Cpath d='M160 175 l-10 5 10 5 -2 -5 z'/%3E%3Ccircle cx='210' cy='185' r='4'/%3E%3Cpath d='M240 175 q-10 10 -20 0'/%3E%3Cpath d='M40 240 q15 -10 30 0 t30 0'/%3E%3Cpath d='M130 235 l5 10 5 -10 z'/%3E%3Cpath d='M180 245 q15 -10 30 0'/%3E%3C/svg%3E");

.conversation--container {
  display: flex;
  flex-direction: column;
  flex: 1;
  overflow-y: auto;
  color-scheme: light dark;
  background-color: $wa-bg-light;
  background-image: $wa-doodle;
  background-repeat: repeat;
  background-attachment: local;

  &.light-scheme {
    color-scheme: light;
    background-color: $wa-bg-light;
  }

  &.dark-scheme {
    color-scheme: dark;
    background-color: $wa-bg-dark;
  }
}

.conversation-wrap {
  flex: 1;
  @apply px-3 pt-6 pb-2;
}

.message--loader {
  text-align: center;
}
</style>
