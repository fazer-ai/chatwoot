<script>
import { ref, provide, useTemplateRef } from 'vue';
import { useElementSize } from '@vueuse/core';
// composable
import { useLabelSuggestions } from 'dashboard/composables/useLabelSuggestions';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useAlert, usePendingAlert } from 'dashboard/composables';

// components
import ReplyBox from './ReplyBox.vue';
import MessageList from 'next/message/MessageList.vue';
import ConversationLabelSuggestion from './conversation/LabelSuggestion.vue';
import Banner from 'dashboard/components/ui/Banner.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ResizableEditorWrapper from './ResizableEditorWrapper.vue';

// stores and apis
import { mapGetters } from 'vuex';

// mixins
import inboxMixin, { INBOX_FEATURES } from 'shared/mixins/inboxMixin';

// utils
import { emitter } from 'shared/helpers/mitt';
import { getTypingUsersText } from '../../../helper/commons';
import { calculateScrollTop } from './helpers/scrollTopCalculationHelper';
import { LocalStorage } from 'shared/helpers/localStorage';
import {
  filterDuplicateSourceMessages,
  getReadMessages,
  getUnreadMessages,
} from 'dashboard/helper/conversationHelper';

// constants
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { REPLY_POLICY } from 'shared/constants/links';
import wootConstants from 'dashboard/constants/globals';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import WhatsappLinkDeviceModal from '../../../routes/dashboard/settings/inbox/components/WhatsappLinkDeviceModal.vue';
import { isInboxAdminInGroup } from 'dashboard/helper/phoneHelper';
import {
  isReachoutRestricted,
  reachoutRestrictionDeadline,
  isMessageCapped,
  isMessageCapReached,
  messageCapQuota,
} from 'dashboard/helper/whatsapp';

export default {
  components: {
    MessageList,
    ReplyBox,
    Banner,
    ConversationLabelSuggestion,
    Spinner,
    ResizableEditorWrapper,
    WhatsappLinkDeviceModal,
  },
  mixins: [inboxMixin],
  setup() {
    const { isAdmin } = useAdmin();
    const isPopOutReplyBox = ref(false);
    const conversationPanelRef = ref(null);
    const resizableEditorWrapperRef = ref(null);
    const messagesViewRef = useTemplateRef('messagesViewRef');
    const topBannerRef = useTemplateRef('topBannerRef');
    const { height: containerHeight } = useElementSize(messagesViewRef);
    const { height: topBannerHeight } = useElementSize(topBannerRef);

    const keyboardEvents = {
      Escape: {
        action: () => {
          isPopOutReplyBox.value = false;
        },
      },
    };

    useKeyboardEvents(keyboardEvents);

    const {
      captainTasksEnabled,
      isLabelSuggestionFeatureEnabled,
      getLabelSuggestions,
    } = useLabelSuggestions();

    provide('contextMenuElementTarget', conversationPanelRef);

    return {
      captainTasksEnabled,
      getLabelSuggestions,
      isLabelSuggestionFeatureEnabled,
      conversationPanelRef,
      resizableEditorWrapperRef,
      messagesViewRef,
      topBannerRef,
      containerHeight,
      topBannerHeight,
      isAdmin,
      isPopOutReplyBox,
    };
  },
  data() {
    return {
      isLoadingPrevious: true,
      heightBeforeLoad: null,
      conversationPanel: null,
      hasUserScrolled: false,
      isProgrammaticScroll: false,
      messageSentSinceOpened: false,
      labelSuggestions: [],
      showLinkDeviceModal: false,
    };
  },

  computed: {
    ...mapGetters({
      currentChat: 'getSelectedChat',
      currentUserId: 'getCurrentUserID',
      currentUser: 'getCurrentUser',
      listLoadingStatus: 'getAllMessagesLoaded',
      currentAccountId: 'getCurrentAccountId',
      globalConfig: 'globalConfig/get',
    }),
    currentInbox() {
      return this.$store.getters['inboxes/getInbox'](this.currentChat.inbox_id);
    },
    isOpen() {
      return this.currentChat?.status === wootConstants.STATUS_TYPE.OPEN;
    },
    shouldShowLabelSuggestions() {
      return (
        this.isOpen &&
        this.captainTasksEnabled &&
        this.isLabelSuggestionFeatureEnabled &&
        !this.messageSentSinceOpened
      );
    },
    inboxId() {
      return this.currentChat.inbox_id;
    },
    inbox() {
      return this.$store.getters['inboxes/getInbox'](this.inboxId);
    },
    typingUsersList() {
      const userList = this.$store.getters[
        'conversationTypingStatus/getUserList'
      ](this.currentChat.id);
      return userList;
    },
    isAnyoneTyping() {
      const userList = this.typingUsersList;
      return userList.length !== 0;
    },
    typingUserNames() {
      const userList = this.typingUsersList;
      if (this.isAnyoneTyping) {
        const [i18nKey, params] = getTypingUsersText(userList);
        return this.$t(i18nKey, params);
      }

      return '';
    },
    getMessages() {
      const messages = this.currentChat.messages || [];
      if (this.isAWhatsAppChannel) {
        return filterDuplicateSourceMessages(messages);
      }
      return messages;
    },
    readMessages() {
      return getReadMessages(
        this.getMessages,
        this.currentChat.agent_last_seen_at
      );
    },
    unReadMessages() {
      return getUnreadMessages(
        this.getMessages,
        this.currentChat.agent_last_seen_at
      );
    },
    shouldShowSpinner() {
      return (
        (this.currentChat && this.currentChat.dataFetched === undefined) ||
        (!this.listLoadingStatus && this.isLoadingPrevious)
      );
    },
    // Check there is a instagram inbox exists with the same instagram_id
    hasDuplicateInstagramInbox() {
      const instagramId = this.inbox.instagram_id;
      const { additional_attributes: additionalAttributes = {} } = this.inbox;
      const instagramInbox =
        this.$store.getters['inboxes/getInstagramInboxByInstagramId'](
          instagramId
        );

      return (
        this.inbox.channel_type === INBOX_TYPES.FB &&
        additionalAttributes.type === 'instagram_direct_message' &&
        instagramInbox
      );
    },

    replyWindowBannerMessage() {
      if (this.isAWhatsAppChannel) {
        return this.$t('CONVERSATION.TWILIO_WHATSAPP_CAN_REPLY');
      }
      if (this.isAPIInbox) {
        const { additional_attributes: additionalAttributes = {} } = this.inbox;
        if (additionalAttributes) {
          const {
            agent_reply_time_window_message: agentReplyTimeWindowMessage,
            agent_reply_time_window: agentReplyTimeWindow,
          } = additionalAttributes;
          return (
            agentReplyTimeWindowMessage ||
            this.$t('CONVERSATION.API_HOURS_WINDOW', {
              hours: agentReplyTimeWindow,
            })
          );
        }
        return '';
      }
      return this.$t('CONVERSATION.CANNOT_REPLY');
    },
    replyWindowLink() {
      if (this.isAFacebookInbox || this.isAnInstagramChannel) {
        return REPLY_POLICY.FACEBOOK;
      }
      if (this.isAWhatsAppCloudChannel) {
        return REPLY_POLICY.WHATSAPP_CLOUD;
      }
      if (this.isATiktokChannel) {
        return REPLY_POLICY.TIKTOK;
      }
      if (!this.isAPIInbox) {
        return REPLY_POLICY.TWILIO_WHATSAPP;
      }
      return '';
    },
    replyWindowLinkText() {
      if (
        this.isAWhatsAppChannel ||
        this.isAFacebookInbox ||
        this.isAnInstagramChannel
      ) {
        return this.$t('CONVERSATION.24_HOURS_WINDOW');
      }
      if (this.isATiktokChannel) {
        return this.$t('CONVERSATION.48_HOURS_WINDOW');
      }
      if (!this.isAPIInbox) {
        return this.$t('CONVERSATION.TWILIO_WHATSAPP_24_HOURS_WINDOW');
      }
      return '';
    },
    unreadMessageCount() {
      return this.currentChat.unread_count || 0;
    },
    unreadMessageLabel() {
      const count =
        this.unreadMessageCount > 9 ? '9+' : this.unreadMessageCount;
      const label =
        this.unreadMessageCount > 1
          ? 'CONVERSATION.UNREAD_MESSAGES'
          : 'CONVERSATION.UNREAD_MESSAGE';
      return `${count} ${this.$t(label)}`;
    },
    inboxSupportsReplyTo() {
      const incoming = this.inboxHasFeature(INBOX_FEATURES.REPLY_TO);
      const outgoing =
        this.inboxHasFeature(INBOX_FEATURES.REPLY_TO_OUTGOING) &&
        !this.is360DialogWhatsAppChannel;

      return { incoming, outgoing };
    },
    inboxSupportsEdit() {
      // Currently only Baileys WhatsApp channel supports message editing
      return this.isAWhatsAppBaileysChannel;
    },
    inboxSupportsReactions() {
      return (
        this.isAWhatsAppCloudChannel ||
        this.isAWhatsAppBaileysChannel ||
        this.isAWhatsAppZapiChannel
      );
    },
    currentContact() {
      const senderId = this.currentChat?.meta?.sender?.id;
      if (!senderId) return {};
      return this.$store.getters['contacts/getContact'](senderId);
    },
    isGroupConversation() {
      return this.currentChat?.group_type === 'group';
    },
    groupContactId() {
      return this.currentChat?.meta?.sender?.id || null;
    },
    groupMembers() {
      if (!this.groupContactId) return [];
      return (
        this.$store.getters['groupMembers/getGroupMembers'](
          this.groupContactId
        ) || []
      );
    },
    groupMembersMeta() {
      if (!this.groupContactId) return {};
      return (
        this.$store.getters['groupMembers/getGroupMembersMeta'](
          this.groupContactId
        ) || {}
      );
    },
    isInboxAdminInCurrentGroup() {
      const meta = this.groupMembersMeta;
      if (meta.is_inbox_admin != null) return meta.is_inbox_admin;
      const inboxPhone = meta.inbox_phone_number || this.inbox?.phone_number;
      return isInboxAdminInGroup(inboxPhone, this.groupMembers);
    },
    isGroupMembersLoaded() {
      const meta = this.groupMembersMeta;
      return meta.is_inbox_admin != null || this.groupMembers.length > 0;
    },
    isAnnouncementModeRestricted() {
      return (
        this.isAWhatsAppBaileysChannel &&
        this.isGroupConversation &&
        this.currentContact?.additional_attributes?.announce === true &&
        this.isGroupMembersLoaded &&
        !this.isInboxAdminInCurrentGroup
      );
    },
    isGroupLeft() {
      return (
        this.isAWhatsAppBaileysChannel &&
        this.isGroupConversation &&
        this.currentContact?.additional_attributes?.group_left === true
      );
    },
    isGroupsDisabled() {
      return (
        this.isAWhatsAppBaileysChannel &&
        this.isGroupConversation &&
        !this.globalConfig.baileysWhatsappGroupsEnabled
      );
    },
    isSuperAdmin() {
      return this.currentUser.type === 'SuperAdmin';
    },
    inboxProviderConnection() {
      return this.currentInbox.provider_connection?.connection;
    },
    inboxReachoutLock() {
      return this.currentInbox.provider_connection?.reachout_time_lock;
    },
    showReachoutRestriction() {
      return isReachoutRestricted(
        this.inboxReachoutLock,
        this.inboxProviderConnection
      );
    },
    reachoutRestrictionMessage() {
      const deadline = reachoutRestrictionDeadline(this.inboxReachoutLock);
      return deadline
        ? this.$t(
            'CONVERSATION.INBOX.WHATSAPP_REACHOUT_RESTRICTION.RESTRICTED_UNTIL',
            { time: deadline }
          )
        : this.$t(
            'CONVERSATION.INBOX.WHATSAPP_REACHOUT_RESTRICTION.RESTRICTED'
          );
    },
    inboxNewChatCap() {
      return this.currentInbox.provider_connection?.new_chat_cap;
    },
    showMessageCap() {
      return isMessageCapped(
        this.inboxNewChatCap,
        this.inboxProviderConnection
      );
    },
    messageCapBannerScheme() {
      return isMessageCapReached(this.inboxNewChatCap) ? 'alert' : 'warning';
    },
    messageCapMessage() {
      const quota = messageCapQuota(this.inboxNewChatCap);
      if (isMessageCapReached(this.inboxNewChatCap)) {
        return quota
          ? this.$t(
              'CONVERSATION.INBOX.WHATSAPP_NEW_CHAT_CAP.CAPPED_WITH_QUOTA',
              quota
            )
          : this.$t('CONVERSATION.INBOX.WHATSAPP_NEW_CHAT_CAP.CAPPED');
      }
      return quota
        ? this.$t(
            'CONVERSATION.INBOX.WHATSAPP_NEW_CHAT_CAP.WARNING_WITH_QUOTA',
            quota
          )
        : this.$t('CONVERSATION.INBOX.WHATSAPP_NEW_CHAT_CAP.WARNING');
    },
  },

  watch: {
    currentChat(newChat, oldChat) {
      if (newChat.id === oldChat.id) {
        return;
      }
      this.fetchAllAttachmentsFromCurrentChat();
      this.fetchSuggestions();
      this.messageSentSinceOpened = false;
      this.resetReplyEditorHeight();
    },
    groupContactId: {
      immediate: true,
      handler(contactId) {
        if (
          contactId &&
          this.isAWhatsAppBaileysChannel &&
          this.isGroupConversation &&
          !this.isGroupMembersLoaded
        ) {
          this.$store.dispatch('groupMembers/fetch', {
            contactId,
          });
        }
      },
    },
  },

  created() {
    emitter.on(BUS_EVENTS.SCROLL_TO_MESSAGE, this.onScrollToMessage);
    // when a message is sent we set the flag to true this hides the label suggestions,
    // until the chat is changed and the flag is reset in the watch for currentChat
    emitter.on(BUS_EVENTS.MESSAGE_SENT, () => {
      this.messageSentSinceOpened = true;
    });
  },

  mounted() {
    this.addScrollListener();
    this.fetchAllAttachmentsFromCurrentChat();
    this.fetchSuggestions();
  },

  unmounted() {
    this.removeBusListeners();
    this.removeScrollListener();
  },

  methods: {
    async fetchSuggestions() {
      // start empty, this ensures that the label suggestions are not shown
      this.labelSuggestions = [];

      if (this.isLabelSuggestionDismissed()) {
        return;
      }

      // Early exit if conversation already has labels - no need to suggest more
      const existingLabels = this.currentChat?.labels || [];
      if (existingLabels.length > 0) return;

      if (!this.captainTasksEnabled || !this.isLabelSuggestionFeatureEnabled) {
        return;
      }

      this.labelSuggestions = await this.getLabelSuggestions();

      // once the labels are fetched, we need to scroll to bottom
      // but we need to wait for the DOM to be updated
      // so we use the nextTick method
      this.$nextTick(() => {
        // this param is added to route, telling the UI to navigate to the message
        // it is triggered by the SCROLL_TO_MESSAGE method
        // see setActiveChat on ConversationView.vue for more info
        const { messageId } = this.$route.query;

        // only trigger the scroll to bottom if the user has not scrolled
        // and there's no active messageId that is selected in view
        if (!messageId && !this.hasUserScrolled) {
          this.scrollToBottom();
        }
      });
    },
    isLabelSuggestionDismissed() {
      return LocalStorage.getFlag(
        LOCAL_STORAGE_KEYS.DISMISSED_LABEL_SUGGESTIONS,
        this.currentAccountId,
        this.currentChat.id
      );
    },
    fetchAllAttachmentsFromCurrentChat() {
      this.$store.dispatch('fetchAllAttachments', this.currentChat.id);
    },
    removeBusListeners() {
      emitter.off(BUS_EVENTS.SCROLL_TO_MESSAGE, this.onScrollToMessage);
    },
    onScrollToMessage({ messageId = '' } = {}) {
      this.$nextTick(() => {
        const messageElement = document.getElementById('message' + messageId);
        if (messageElement) {
          this.isProgrammaticScroll = true;
          messageElement.scrollIntoView({ behavior: 'smooth' });
          if (messageId) {
            emitter.emit(BUS_EVENTS.HIGHLIGHT_MESSAGE, { messageId });
          }
        } else if (messageId) {
          this.fetchAndScrollToMessage(messageId);
        } else {
          this.scrollToBottom();
        }
      });
      this.makeMessagesRead();
    },
    async fetchAndScrollToMessage(messageId) {
      const dismissSearch = usePendingAlert(
        this.$t('SCHEDULED_MESSAGES.ITEM.SEARCHING_MESSAGE')
      );
      try {
        await this.$store.dispatch('fetchPreviousMessages', {
          conversationId: this.currentChat.id,
          after: messageId,
        });
        this.$nextTick(() => {
          dismissSearch();
          const messageElement = document.getElementById('message' + messageId);
          if (messageElement) {
            this.isProgrammaticScroll = true;
            messageElement.scrollIntoView({ behavior: 'smooth' });
            emitter.emit(BUS_EVENTS.HIGHLIGHT_MESSAGE, { messageId });
          } else {
            useAlert(this.$t('SCHEDULED_MESSAGES.ITEM.MESSAGE_NOT_FOUND'));
          }
        });
      } catch {
        dismissSearch();
        useAlert(this.$t('SCHEDULED_MESSAGES.ITEM.MESSAGE_NOT_FOUND'));
      }
    },
    addScrollListener() {
      this.conversationPanel = this.$el.querySelector('.conversation-panel');
      this.setScrollParams();
      this.conversationPanel.addEventListener('scroll', this.handleScroll);
      this.$nextTick(() => this.scrollToBottom());
      this.isLoadingPrevious = false;
    },
    removeScrollListener() {
      this.conversationPanel.removeEventListener('scroll', this.handleScroll);
    },
    scrollToBottom() {
      this.isProgrammaticScroll = true;
      let relevantMessages = [];

      // label suggestions are not part of the messages list
      // so we need to handle them separately
      let labelSuggestions =
        this.conversationPanel.querySelector('.label-suggestion');

      // if there are unread messages, scroll to the first unread message
      if (this.unreadMessageCount > 0) {
        // capturing only the unread messages
        relevantMessages =
          this.conversationPanel.querySelectorAll('.message--unread');
      } else if (labelSuggestions) {
        // when scrolling to the bottom, the label suggestions is below the last message
        // so we scroll there if there are no unread messages
        // Unread messages always take the highest priority
        relevantMessages = [labelSuggestions];
      } else {
        // if there are no unread messages or label suggestion, scroll to the last message
        // capturing last message from the messages list
        relevantMessages = Array.from(
          this.conversationPanel.querySelectorAll('.message--read')
        ).slice(-1);
      }

      this.conversationPanel.scrollTop = calculateScrollTop(
        this.conversationPanel.scrollHeight,
        this.$el.scrollHeight,
        relevantMessages
      );
    },
    setScrollParams() {
      this.heightBeforeLoad = this.conversationPanel.scrollHeight;
      this.scrollTopBeforeLoad = this.conversationPanel.scrollTop;
    },

    async fetchPreviousMessages(scrollTop = 0) {
      this.setScrollParams();
      const shouldLoadMoreMessages =
        this.currentChat.dataFetched === true &&
        !this.listLoadingStatus &&
        !this.isLoadingPrevious;

      if (
        scrollTop < 100 &&
        !this.isLoadingPrevious &&
        shouldLoadMoreMessages
      ) {
        this.isLoadingPrevious = true;
        try {
          await this.$store.dispatch('fetchPreviousMessages', {
            conversationId: this.currentChat.id,
            before: this.currentChat.messages[0].id,
          });
          const heightDifference =
            this.conversationPanel.scrollHeight - this.heightBeforeLoad;
          this.conversationPanel.scrollTop =
            this.scrollTopBeforeLoad + heightDifference;
          this.setScrollParams();
        } catch (error) {
          // Ignore Error
        } finally {
          this.isLoadingPrevious = false;
        }
      }
    },

    handleScroll(e) {
      if (this.isProgrammaticScroll) {
        // Reset the flag
        this.isProgrammaticScroll = false;
        this.hasUserScrolled = false;
      } else {
        this.hasUserScrolled = true;
      }
      emitter.emit(BUS_EVENTS.ON_MESSAGE_LIST_SCROLL);
      this.fetchPreviousMessages(e.target.scrollTop);
    },

    makeMessagesRead() {
      this.$store.dispatch('markMessagesRead', { id: this.currentChat.id });
    },
    async handleMessageRetry(message) {
      if (!message) return;
      const payload = useSnakeCase(message);
      await this.$store.dispatch('sendMessageWithData', payload);
    },
    async handleToggleReaction({ messageId, targetSourceId, emoji }) {
      // Backend keeps a single Message row per (target, user) and toggles it
      // in-place. The cable echo always carries the original create's echo_id,
      // so creating a fresh optimistic per toggle leaves the new one orphaned
      // in the store (the cable matches the real msg id, never the new echo).
      // Those orphans show up as "reagiu <emoji>" in the chat list preview
      // even after the user toggles off. Update the existing entry instead.
      const existing = this.findCurrentUserReaction(messageId, targetSourceId);
      if (existing) {
        await this.applyToggleOnExisting(existing, messageId, emoji);
      } else {
        await this.applyToggleOnNew(messageId, emoji);
      }
    },
    async applyToggleOnExisting(existing, messageId, emoji) {
      const isActive =
        existing.content && !existing.content_attributes?.deleted;
      const isToggleOff =
        isActive && (emoji === '' || existing.content === emoji);
      const newAttrs = { ...(existing.content_attributes || {}) };
      if (isToggleOff) newAttrs.deleted = true;
      else delete newAttrs.deleted;

      const previous = {
        content: existing.content,
        content_attributes: existing.content_attributes,
      };
      this.$store.dispatch('updateMessage', {
        ...existing,
        content: isToggleOff ? '' : emoji,
        content_attributes: newAttrs,
      });

      try {
        await this.$store.dispatch('toggleMessageReaction', {
          conversationId: this.currentChat.id,
          messageId,
          emoji,
          echoId: existing.echo_id,
        });
      } catch (error) {
        this.$store.dispatch('updateMessage', { ...existing, ...previous });
        useAlert(this.$t('CONVERSATION.REACTIONS.FAILED'));
      }
    },
    async applyToggleOnNew(messageId, emoji) {
      const optimistic = this.buildOptimisticReaction(messageId, emoji);
      this.$store.dispatch('addMessage', optimistic);

      try {
        await this.$store.dispatch('toggleMessageReaction', {
          conversationId: this.currentChat.id,
          messageId,
          emoji,
          echoId: optimistic.echo_id,
        });
      } catch (error) {
        this.$store.dispatch('updateMessage', {
          ...optimistic,
          content_attributes: {
            ...optimistic.content_attributes,
            deleted: true,
          },
        });
        useAlert(this.$t('CONVERSATION.REACTIONS.FAILED'));
      }
    },
    findCurrentUserReaction(messageId, targetSourceId = null) {
      const messages = this.currentChat?.messages || [];
      const matches = messages.filter(m => {
        if (!m.content_attributes?.is_reaction) return false;
        // Match both in_reply_to (set by Chatwoot-originated reactions) and
        // in_reply_to_external_id (set by WhatsApp echoes). Without the
        // external id check, a multi-device reaction sent from the connected
        // phone would be invisible here, and the next toggle would stack a
        // duplicate optimistic row instead of mutating the echoed one.
        const matchesInReplyTo =
          m.content_attributes?.in_reply_to === messageId;
        const matchesExternalId =
          targetSourceId &&
          m.content_attributes?.in_reply_to_external_id === targetSourceId;
        if (!matchesInReplyTo && !matchesExternalId) return false;
        // REST jbuilder doesn't surface sender_type; only the nested
        // sender.type. ActionCable push_event_data has the top-level field.
        // Read both so REST-loaded agent reactions match instead of stacking
        // a duplicate optimistic row.
        const senderType = (
          m.sender_type ||
          m.sender?.type ||
          ''
        ).toLowerCase();
        const senderId = m.sender?.id ?? m.sender_id;
        // Reaction created via Chatwoot UI by the current user
        if (senderType === 'user' && senderId === this.currentUserId) {
          return true;
        }
        // Multi-device echo: agent reacted from the WhatsApp mobile app on
        // the same number connected to this inbox, so it has no agent in
        // Chatwoot. Treat it as ours so a click toggles/removes it instead
        // of stacking a duplicate reaction on top.
        return m.message_type === 1 && senderId == null;
      });
      // Prefer active rows so we never resurrect a stale deleted echo when
      // there is a fresher live reaction sitting next to it. created_at is
      // second-resolution, so a sort can keep the older entry first on ties.
      // Reduce with >= so that, all else equal, the later iteration wins —
      // giving a deterministic "newest" pick even for two toggles in the same
      // second.
      const pickLatest = list =>
        list.reduce((latest, candidate) => {
          if (!latest) return candidate;
          return (candidate.created_at || 0) >= (latest.created_at || 0)
            ? candidate
            : latest;
        }, null);
      const isActive = r => !!r.content && !r.content_attributes?.deleted;
      return pickLatest(matches.filter(isActive)) || pickLatest(matches);
    },
    buildOptimisticReaction(messageId, emoji) {
      // Use the echo_id as the temporary id so findPendingMessageIndex matches
      // the real Message arriving later via ActionCable (it carries echo_id).
      const echoId = `optimistic-${Date.now()}-${Math.random().toString(36).slice(2)}`;

      return {
        id: echoId,
        echo_id: echoId,
        content: emoji,
        conversation_id: this.currentChat?.id,
        message_type: 1,
        content_type: 'text',
        content_attributes: {
          is_reaction: true,
          in_reply_to: messageId,
        },
        additional_attributes: {},
        attachments: [],
        sender: this.currentUser,
        sender_type: 'User',
        sender_id: this.currentUserId,
        private: false,
        status: 'progress',
        created_at: Math.floor(Date.now() / 1000),
      };
    },
    toggleReplyEditorSize() {
      this.resizableEditorWrapperRef?.toggleEditorExpand?.();
    },
    resetReplyEditorHeight() {
      this.resizableEditorWrapperRef?.resetEditorHeight?.();
    },
    getInReplyToMessage(parentMessage) {
      if (!parentMessage) return {};
      const inReplyToMessageId = parentMessage.content_attributes?.in_reply_to;
      if (!inReplyToMessageId) return {};

      return this.currentChat?.messages.find(message => {
        if (message.id === inReplyToMessageId) {
          return true;
        }
        return false;
      });
    },
    onOpenGroupsEnabledLink() {
      window.open(wootConstants.FAZER_AI_GUIDES_URL, '_blank');
    },
    onOpenLinkDeviceModal() {
      this.showLinkDeviceModal = true;
    },
    onCloseLinkDeviceModal() {
      this.showLinkDeviceModal = false;
    },
    onSetupProviderConnection() {
      this.$store
        .dispatch('inboxes/setupChannelProvider', this.inbox.id)
        .catch(e => {
          // eslint-disable-next-line no-console
          console.error('Error setting up provider connection:', e);
          useAlert(
            this.$t(
              'CONVERSATION.INBOX.WHATSAPP_PROVIDER_CONNECTION.RECONNECT_FAILED'
            )
          );
        });
    },
  },
};
</script>

<template>
  <div
    ref="messagesViewRef"
    class="flex flex-col justify-between flex-grow h-full min-w-0 m-0"
  >
    <div ref="topBannerRef">
      <template v-if="isAWhatsAppBaileysChannel || isAWhatsAppZapiChannel">
        <WhatsappLinkDeviceModal
          v-if="showLinkDeviceModal"
          :show="showLinkDeviceModal"
          :on-close="onCloseLinkDeviceModal"
          :inbox="currentInbox"
        />
        <Banner
          v-if="inboxProviderConnection !== 'open'"
          color-scheme="alert"
          class="mt-2 mx-2 rounded-lg overflow-hidden"
          :banner-message="
            isAdmin
              ? $t(
                  'CONVERSATION.INBOX.WHATSAPP_PROVIDER_CONNECTION.NOT_CONNECTED'
                )
              : $t(
                  'CONVERSATION.INBOX.WHATSAPP_PROVIDER_CONNECTION.NOT_CONNECTED_CONTACT_ADMIN'
                )
          "
          has-action-button
          :action-button-label="
            isAdmin
              ? $t(
                  'CONVERSATION.INBOX.WHATSAPP_PROVIDER_CONNECTION.LINK_DEVICE'
                )
              : ''
          "
          :action-button-icon="isAdmin ? '' : 'i-lucide-refresh-cw'"
          @primary-action="
            isAdmin ? onOpenLinkDeviceModal() : onSetupProviderConnection()
          "
        />
        <Banner
          v-if="showReachoutRestriction"
          color-scheme="alert"
          class="mt-2 mx-2 rounded-lg overflow-hidden"
          :banner-message="reachoutRestrictionMessage"
        />
        <Banner
          v-if="showMessageCap"
          :color-scheme="messageCapBannerScheme"
          class="mt-2 mx-2 rounded-lg overflow-hidden"
          :banner-message="messageCapMessage"
        />
      </template>
      <Banner
        v-if="!currentChat.can_reply"
        color-scheme="alert"
        class="mx-2 mt-2 overflow-hidden rounded-lg"
        :banner-message="replyWindowBannerMessage"
        :href-link="replyWindowLink"
        :href-link-text="replyWindowLinkText"
      />
      <Banner
        v-else-if="hasDuplicateInstagramInbox"
        color-scheme="alert"
        class="mx-2 mt-2 overflow-hidden rounded-lg"
        :banner-message="$t('CONVERSATION.OLD_INSTAGRAM_INBOX_REPLY_BANNER')"
      />
      <Banner
        v-else-if="isGroupLeft"
        color-scheme="alert"
        class="mx-2 mt-2 overflow-hidden rounded-lg"
        :banner-message="$t('CONVERSATION.GROUP_LEFT_BANNER')"
      />
      <Banner
        v-else-if="isAnnouncementModeRestricted"
        color-scheme="alert"
        class="mx-2 mt-2 overflow-hidden rounded-lg"
        :banner-message="$t('CONVERSATION.ANNOUNCEMENT_MODE_BANNER')"
      />
      <Banner
        v-if="isGroupsDisabled && isSuperAdmin"
        color-scheme="warning"
        class="mx-2 mt-2 overflow-hidden rounded-lg"
        :banner-message="$t('CONVERSATION.GROUPS_DISABLED_BANNER')"
        :notice-message="$t('GENERAL_SETTINGS.SUPER_ADMIN_ONLY_NOTICE')"
        has-action-button
        :action-button-label="$t('CONVERSATION.GROUPS_DISABLED_CTA')"
        @primary-action="onOpenGroupsEnabledLink"
      />
      <Banner
        v-else-if="isGroupsDisabled"
        color-scheme="warning"
        class="mx-2 mt-2 overflow-hidden rounded-lg"
        :banner-message="$t('CONVERSATION.GROUPS_DISABLED_BANNER_NON_ADMIN')"
      />
    </div>
    <MessageList
      ref="conversationPanelRef"
      class="conversation-panel flex-shrink flex-grow basis-px flex flex-col overflow-y-auto relative h-full m-0 pb-4"
      :current-user-id="currentUserId"
      :first-unread-id="unReadMessages[0]?.id"
      :is-an-email-channel="isAnEmailChannel"
      :inbox-supports-reply-to="inboxSupportsReplyTo"
      :inbox-supports-edit="inboxSupportsEdit"
      :inbox-supports-reactions="inboxSupportsReactions"
      :messages="getMessages"
      @retry="handleMessageRetry"
      @toggle-reaction="handleToggleReaction"
    >
      <template #beforeAll>
        <transition name="slide-up">
          <!-- eslint-disable-next-line vue/require-toggle-inside-transition -->
          <li
            class="min-h-[4rem] flex flex-shrink-0 flex-grow-0 items-center flex-auto justify-center max-w-full mt-0 mr-0 mb-1 ml-0 relative first:mt-auto last:mb-0"
          >
            <Spinner v-if="shouldShowSpinner" class="text-n-brand" />
          </li>
        </transition>
      </template>
      <template #unreadBadge>
        <li
          v-show="unreadMessageCount != 0"
          class="list-none flex justify-center items-center"
        >
          <span
            class="shadow-lg rounded-full bg-n-brand text-white text-xs font-medium my-2.5 mx-auto px-2.5 py-1.5"
          >
            {{ unreadMessageLabel }}
          </span>
        </li>
      </template>
      <template #after>
        <ConversationLabelSuggestion
          v-if="shouldShowLabelSuggestions"
          :suggested-labels="labelSuggestions"
          :chat-labels="currentChat.labels"
          :conversation-id="currentChat.id"
        />
      </template>
    </MessageList>
    <div class="flex relative flex-col bg-n-surface-1">
      <div
        v-if="isAnyoneTyping"
        class="absolute flex items-center w-full h-0 -top-7"
      >
        <div
          class="flex py-2 pr-4 pl-5 shadow-md rounded-full bg-white dark:bg-n-solid-3 text-n-slate-11 text-xs font-semibold my-2.5 mx-auto"
        >
          {{ typingUserNames }}
          <img
            class="w-6 ltr:ml-2 rtl:mr-2"
            src="assets/images/typing.gif"
            alt="Someone is typing"
          />
        </div>
      </div>
      <ResizableEditorWrapper
        ref="resizableEditorWrapperRef"
        :container-height="Math.max(0, containerHeight - topBannerHeight)"
      >
        <ReplyBox @toggle-editor-size="toggleReplyEditorSize" />
      </ResizableEditorWrapper>
    </div>
  </div>
</template>
