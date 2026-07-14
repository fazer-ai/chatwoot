<script>
import UserMessage from 'simulator/components/UserMessage.vue';
import AgentMessageBubble from 'simulator/components/AgentMessageBubble.vue';
import MessageReplyButton from 'simulator/components/MessageReplyButton.vue';
import { messageStamp } from 'shared/helpers/timeHelper';
import ImageBubble from 'simulator/components/ImageBubble.vue';
import VideoBubble from 'simulator/components/VideoBubble.vue';
import FileBubble from 'simulator/components/FileBubble.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { MESSAGE_TYPE } from 'simulator/helpers/constants';
import configMixin from '../mixins/configMixin';
import messageMixin from '../mixins/messageMixin';
import { isASubmittedFormMessage } from 'shared/helpers/MessageTypeHelper';
import ReplyToChip from 'simulator/components/ReplyToChip.vue';
import MessageReactionTrigger from 'simulator/components/MessageReactionTrigger.vue';
import MessageReactionChips from 'simulator/components/MessageReactionChips.vue';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';

export default {
  name: 'AgentMessage',
  components: {
    AgentMessageBubble,
    ImageBubble,
    VideoBubble,
    Avatar,
    UserMessage,
    FileBubble,
    MessageReplyButton,
    ReplyToChip,
    MessageReactionTrigger,
    MessageReactionChips,
  },
  mixins: [configMixin, messageMixin],
  props: {
    message: {
      type: Object,
      default: () => {},
    },
    replyTo: {
      type: Object,
      default: () => {},
    },
  },
  data() {
    return {
      hasImageError: false,
      hasVideoError: false,
    };
  },
  computed: {
    shouldDisplayAgentMessage() {
      if (
        this.contentType === 'input_select' &&
        this.messageContentAttributes.submitted_values &&
        !this.message.content
      ) {
        return false;
      }
      return this.message.content;
    },
    readableTime() {
      const { created_at: createdAt = '' } = this.message;
      return messageStamp(createdAt, 'LLL d yyyy, h:mm a');
    },
    messageType() {
      const { message_type: type = 1 } = this.message;
      return type;
    },
    contentType() {
      const { content_type: type = '' } = this.message;
      return type;
    },
    agentName() {
      if (this.message.sender) {
        return this.message.sender.available_name || this.message.sender.name;
      }

      if (this.message.additional_attributes?.sender_name) {
        return this.message.additional_attributes.sender_name;
      }

      if (this.useInboxAvatarForBot) {
        return this.channelConfig.websiteName;
      }

      return this.$t('UNREAD_VIEW.BOT');
    },
    avatarUrl() {
      const displayImage = this.useInboxAvatarForBot
        ? this.inboxAvatarUrl
        : '/assets/images/chatwoot_bot.png';

      if (this.message.message_type === MESSAGE_TYPE.TEMPLATE) {
        return displayImage;
      }

      if (this.message.sender) {
        return this.message.sender.avatar_url;
      }

      return (
        this.message.additional_attributes?.sender_avatar_url || displayImage
      );
    },
    hasRecordedResponse() {
      return (
        this.messageContentAttributes.submitted_email ||
        (this.messageContentAttributes.submitted_values &&
          !['form', 'input_csat'].includes(this.contentType))
      );
    },
    responseMessage() {
      if (this.messageContentAttributes.submitted_email) {
        return { content: this.messageContentAttributes.submitted_email };
      }

      if (this.messageContentAttributes.submitted_values) {
        if (this.contentType === 'input_select') {
          const [selectionOption = {}] =
            this.messageContentAttributes.submitted_values;
          return { content: selectionOption.title || selectionOption.value };
        }
      }
      return '';
    },
    isASubmittedForm() {
      return isASubmittedFormMessage(this.message);
    },
    submittedFormValues() {
      return this.messageContentAttributes.submitted_values.map(
        submittedValue => ({
          id: submittedValue.name,
          content: submittedValue.value,
        })
      );
    },
    wrapClass() {
      return {
        'has-text': this.shouldDisplayAgentMessage,
      };
    },
    hasReplyTo() {
      return this.replyTo && (this.replyTo.content || this.replyTo.attachments);
    },
    // Only show the AurisChat feedback flag when the simulator was booted
    // by the dashboard with the integration wired end-to-end
    // (SimulatorModal.vue appends `?simulator=1&clickup=1`). Without
    // both flags the click would post to a dialog the operator can't
    // reach or the ClickUp side would fail to accept.
    canShowSimulatorFeedback() {
      const params = new URLSearchParams(window.location.search);
      return params.get('simulator') === '1' && params.get('clickup') === '1';
    },
  },
  watch: {
    message() {
      this.hasImageError = false;
      this.hasVideoError = false;
    },
  },
  mounted() {
    this.hasImageError = false;
    this.hasVideoError = false;
  },
  methods: {
    onImageLoadError() {
      this.hasImageError = true;
    },
    onVideoLoadError() {
      this.hasVideoError = true;
    },
    toggleReply() {
      emitter.emit(BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE, this.message);
    },
    // Hand off the message id (server pk) to the dashboard parent frame.
    // Same-origin postMessage is safe here — SimulatorModal filters on
    // both `event.origin` and the payload `type` before acting on it.
    openFeedback() {
      window.parent?.postMessage(
        {
          type: 'aurischat:open-feedback',
          messageId: this.message.id,
          conversationId: this.message.conversation_id,
        },
        window.location.origin
      );
    },
  },
};
</script>

<template>
  <div
    class="agent-message-wrap group"
    :class="{
      'has-response': hasRecordedResponse || isASubmittedForm,
    }"
  >
    <div v-if="!isASubmittedForm" class="agent-message">
      <div class="avatar-wrap">
        <div class="user-thumbnail-box">
          <Avatar
            v-if="message.showAvatar || hasRecordedResponse"
            :src="avatarUrl"
            :size="24"
            :name="agentName"
            rounded-full
          />
        </div>
      </div>
      <div class="message-wrap">
        <div v-if="hasReplyTo" class="flex mt-2 mb-1 text-xs">
          <ReplyToChip :reply-to="replyTo" />
        </div>
        <div class="flex w-full gap-1">
          <div
            class="space-y-2"
            :class="{
              'w-full':
                contentType === 'form' &&
                !messageContentAttributes?.submitted_values,
            }"
          >
            <div class="relative">
              <AgentMessageBubble
                v-if="shouldDisplayAgentMessage"
                :content-type="contentType"
                :message-content-attributes="messageContentAttributes"
                :message-id="message.id"
                :message-type="messageType"
                :message="message.content"
                :created-at="message.created_at"
              />
              <MessageReactionChips
                v-if="
                  shouldDisplayAgentMessage && typeof message.id === 'number'
                "
                :message-id="message.id"
              />
            </div>
            <div
              v-if="hasAttachments"
              class="space-y-2 chat-bubble has-attachment agent bg-n-background dark:bg-n-solid-3"
              :class="wrapClass"
            >
              <div
                v-for="attachment in message.attachments"
                :key="attachment.id"
              >
                <ImageBubble
                  v-if="attachment.file_type === 'image' && !hasImageError"
                  :url="attachment.data_url"
                  :thumb="attachment.data_url"
                  :readable-time="readableTime"
                  @error="onImageLoadError"
                />

                <VideoBubble
                  v-if="attachment.file_type === 'video' && !hasVideoError"
                  :url="attachment.data_url"
                  :readable-time="readableTime"
                  @error="onVideoLoadError"
                />

                <audio
                  v-else-if="attachment.file_type === 'audio'"
                  controls
                  class="h-10 dark:invert"
                >
                  <source :src="attachment.data_url" />
                </audio>
                <FileBubble v-else :url="attachment.data_url" />
              </div>
            </div>
          </div>
          <div
            class="flex flex-col items-center gap-1 self-center transition-opacity delay-75 opacity-0 group-hover:opacity-100 sm:opacity-0"
          >
            <MessageReplyButton @click="toggleReply" />
            <MessageReactionTrigger
              v-if="shouldDisplayAgentMessage && typeof message.id === 'number'"
              :message-id="message.id"
              alignment="right"
            />
            <button
              v-if="canShowSimulatorFeedback && typeof message.id === 'number'"
              type="button"
              class="p-1 rounded-full text-n-slate-11 bg-n-slate-3 hover:text-n-slate-12"
              :title="$t('COMPONENTS.SIMULATOR_FEEDBACK.OPEN_BUTTON')"
              :aria-label="$t('COMPONENTS.SIMULATOR_FEEDBACK.OPEN_BUTTON')"
              @click="openFeedback"
            >
              <i class="i-lucide-flag block w-[11px] h-[11px]" />
            </button>
          </div>
        </div>
        <p
          v-if="message.showAvatar || hasRecordedResponse"
          v-dompurify-html="agentName"
          class="agent-name text-n-slate-11"
        />
      </div>
    </div>

    <UserMessage v-if="hasRecordedResponse" :message="responseMessage" />
    <div v-if="isASubmittedForm">
      <UserMessage
        v-for="submittedValue in submittedFormValues"
        :key="submittedValue.id"
        :message="submittedValue"
      />
    </div>
  </div>
</template>
