<script>
import { mapGetters } from 'vuex';

import ChatFooter from '../components/ChatFooter.vue';
import ConversationWrap from '../components/ConversationWrap.vue';

export default {
  components: { ChatFooter, ConversationWrap },
  computed: {
    ...mapGetters({
      groupedMessages: 'conversation/getGroupedConversation',
    }),
  },
  mounted() {
    this.$store.dispatch('conversation/setUserLastSeen');
  },
};
</script>

<template>
  <div class="messages-view flex flex-col flex-1 overflow-hidden rounded-b-lg">
    <div class="flex flex-1 overflow-auto">
      <ConversationWrap :grouped-messages="groupedMessages" />
    </div>
    <ChatFooter class="px-4" />
  </div>
</template>

<style scoped lang="scss">
// Keep the bottom row (input bar) on a flat white background that sits
// flush against the WhatsApp-styled chat area instead of the Chatwoot
// slate fill.
.messages-view {
  background-color: #f0f2f5;
}

:root[data-theme='dark'] .messages-view,
.dark .messages-view {
  background-color: #1f2c34;
}
</style>
