<script>
import { MESSAGE_TYPE } from 'widget/helpers/constants';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { useMapGetter } from 'dashboard/composables/store';
import { ATTACHMENT_ICONS } from 'shared/constants/messages';

export default {
  name: 'MessagePreview',
  props: {
    message: {
      type: Object,
      required: true,
    },
    showMessageType: {
      type: Boolean,
      default: true,
    },
    defaultEmptyMessage: {
      type: String,
      default: '',
    },
  },
  setup() {
    const { getPlainText } = useMessageFormatter();
    const currentUserId = useMapGetter('getCurrentUserID');
    return {
      getPlainText,
      currentUserId,
    };
  },
  computed: {
    isReactionMessage() {
      const attrs = this.message?.content_attributes;
      // Treat removed reactions (deleted toggled or content cleared) as not a
      // reaction so the preview falls back to plain text/no-content branches
      // instead of rendering "X reagiu " with an empty emoji.
      return (
        attrs?.is_reaction === true &&
        !attrs?.deleted &&
        !!this.message?.content
      );
    },
    reactionPreviewText() {
      if (!this.isReactionMessage) return '';
      const senderId = this.message?.sender?.id;
      const isOwnInboxEcho =
        this.message?.message_type === MESSAGE_TYPE.OUTGOING && !senderId;
      const senderName =
        senderId === this.currentUserId || isOwnInboxEcho
          ? this.$t('CONVERSATION.REACTIONS.YOU')
          : this.message?.sender?.name || '';
      const emoji = this.message?.content;
      const snippet = this.message?.in_reply_to_snippet;
      const params = { sender: senderName, emoji, snippet };
      return snippet
        ? this.$t('CHAT_LIST.REACTED_TO_SNIPPET', params)
        : this.$t('CHAT_LIST.REACTED', params);
    },
    messageByAgent() {
      const { message_type: messageType } = this.message;
      return messageType === MESSAGE_TYPE.OUTGOING;
    },
    isMessageAnActivity() {
      const { message_type: messageType } = this.message;
      return messageType === MESSAGE_TYPE.ACTIVITY;
    },
    isMessagePrivate() {
      const { private: isPrivate } = this.message;
      return isPrivate;
    },
    parsedLastMessage() {
      const { content_attributes: contentAttributes } = this.message;
      const { email: { subject } = {} } = contentAttributes || {};
      return this.getPlainText(subject || this.message.content);
    },
    lastMessageFileType() {
      const [{ file_type: fileType } = {}] = this.message.attachments;
      return fileType;
    },
    attachmentIcon() {
      return ATTACHMENT_ICONS[this.lastMessageFileType];
    },
    attachmentMessageContent() {
      return `CHAT_LIST.ATTACHMENTS.${this.lastMessageFileType}.CONTENT`;
    },
    isMessageSticker() {
      return this.message && this.message.content_type === 'sticker';
    },
  },
};
</script>

<template>
  <div class="overflow-hidden text-ellipsis whitespace-nowrap">
    <template v-if="showMessageType">
      <fluent-icon
        v-if="isMessagePrivate"
        size="16"
        class="-mt-0.5 align-middle text-n-slate-11 inline-block"
        icon="lock-closed"
      />
      <fluent-icon
        v-else-if="messageByAgent"
        size="16"
        class="-mt-0.5 align-middle text-n-slate-11 inline-block"
        icon="arrow-reply"
      />
      <fluent-icon
        v-else-if="isMessageAnActivity"
        size="16"
        class="-mt-0.5 align-middle text-n-slate-11 inline-block"
        icon="info"
      />
    </template>
    <span v-if="isReactionMessage">
      {{ reactionPreviewText }}
    </span>
    <span v-else-if="message.content && isMessageSticker">
      <fluent-icon
        size="16"
        class="-mt-0.5 align-middle inline-block text-n-slate-11"
        icon="image"
      />
      {{ $t('CHAT_LIST.ATTACHMENTS.image.CONTENT') }}
    </span>
    <span v-else-if="message.content">
      {{ parsedLastMessage }}
    </span>
    <span v-else-if="message.attachments?.length">
      <fluent-icon
        v-if="attachmentIcon && showMessageType"
        size="16"
        class="-mt-0.5 align-middle inline-block text-n-slate-11"
        :icon="attachmentIcon"
      />
      {{ $t(`${attachmentMessageContent}`) }}
    </span>
    <span v-else>
      {{ defaultEmptyMessage || $t('CHAT_LIST.NO_CONTENT') }}
    </span>
  </div>
</template>
