import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import * as types from '../mutation-types';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import InboxesAPI from '../../api/inboxes';
import WebChannel from '../../api/channel/webChannel';
import FBChannel from '../../api/channel/fbChannel';
import TwilioChannel from '../../api/channel/twilioChannel';
import WhatsappChannel from '../../api/channel/whatsappChannel';
import { throwErrorMessage } from '../utils/api';
import AnalyticsHelper from '../../helper/AnalyticsHelper';
import camelcaseKeys from 'camelcase-keys';
import { ACCOUNT_EVENTS } from '../../helper/AnalyticsHelper/events';
import { channelActions, buildInboxData } from './inboxes/channelActions';
import { mapTemplateCategory } from 'dashboard/routes/dashboard/disparador/helper/disparadorHelper';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isFetchingItem: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
    isUpdatingIMAP: false,
    isUpdatingSMTP: false,
    isSyncingTemplates: false,
    isSubmittingTemplate: false,
  },
};

export const getters = {
  getInboxes($state) {
    return $state.records;
  },
  getAllInboxes($state) {
    return camelcaseKeys($state.records, { deep: true });
  },
  getWhatsAppTemplates: $state => inboxId => {
    const [inbox] = $state.records.filter(
      record => record.id === Number(inboxId)
    );

    const {
      message_templates: whatsAppMessageTemplates,
      additional_attributes: additionalAttributes,
    } = inbox || {};

    const { message_templates: apiInboxMessageTemplates } =
      additionalAttributes || {};
    const messagesTemplates =
      whatsAppMessageTemplates || apiInboxMessageTemplates;

    return messagesTemplates;
  },
  getFilteredWhatsAppTemplates: $state => inboxId => {
    const [inbox] = $state.records.filter(
      record => record.id === Number(inboxId)
    );

    const {
      message_templates: whatsAppMessageTemplates,
      additional_attributes: additionalAttributes,
    } = inbox || {};

    const { message_templates: apiInboxMessageTemplates } =
      additionalAttributes || {};
    const templates = whatsAppMessageTemplates || apiInboxMessageTemplates;

    if (!templates || !Array.isArray(templates)) {
      return [];
    }

    return templates.filter(template => {
      // Ensure template has required properties
      if (!template || !template.status || !template.components) {
        return false;
      }

      // Only show approved templates
      if (template.status.toLowerCase() !== 'approved') {
        return false;
      }

      // Filter out authentication templates
      if (template.category === 'AUTHENTICATION') {
        return false;
      }

      // Filter out CSAT templates (customer_satisfaction_survey and its versions)
      if (
        template.name &&
        template.name.startsWith('customer_satisfaction_survey')
      ) {
        return false;
      }

      // Filter out interactive templates (LIST, PRODUCT, CATALOG), location templates, and call permission templates
      const hasUnsupportedComponents = template.components.some(
        component =>
          ['LIST', 'PRODUCT', 'CATALOG', 'CALL_PERMISSION_REQUEST'].includes(
            component.type
          ) ||
          (component.type === 'HEADER' && component.format === 'LOCATION')
      );

      if (hasUnsupportedComponents) {
        return false;
      }

      return true;
    });
  },
  // Disparador (Beta 0) template selector. Unlike getFilteredWhatsAppTemplates,
  // this must work against the sanitized prod snapshot, which stores templates as
  // {name, status} only — `components` is stripped for PII/egress. So it selects
  // on name + approved status WITHOUT requiring (or surfacing) the components blob,
  // which would otherwise make every snapshot-loaded template disappear in staging.
  //
  // GAP D: accepts an ARRAY of inbox ids (a scalar is normalized to a one-element
  // array for back-compat) and returns the INTERSECTION by template name — only
  // templates approved in EVERY selected inbox. Each returned entry carries
  // `name` + the mapped `category` (GAP A: 'marketing'/'utility'/'authentication'
  // or null when absent). When the same name resolves to DIFFERENT categories
  // across inboxes, `category` is set to null (not silently picked): the template
  // stays in the list but CreateDisparo blocks it, matching the backend, which
  // requires the submitted category to equal the real one in ALL inboxes.
  getDisparadorWhatsAppTemplates: $state => inboxIds => {
    const ids = (Array.isArray(inboxIds) ? inboxIds : [inboxIds])
      .map(Number)
      .filter(id => !Number.isNaN(id));
    if (!ids.length) return [];

    const approvedTemplatesFor = inboxId => {
      const [inbox] = $state.records.filter(
        record => record.id === Number(inboxId)
      );

      const {
        message_templates: whatsAppMessageTemplates,
        additional_attributes: additionalAttributes,
      } = inbox || {};

      const { message_templates: apiInboxMessageTemplates } =
        additionalAttributes || {};
      const templates = whatsAppMessageTemplates || apiInboxMessageTemplates;

      if (!templates || !Array.isArray(templates)) return [];

      return templates.filter(
        template =>
          template &&
          template.name &&
          template.status &&
          template.status.toLowerCase() === 'approved'
      );
    };

    // Build a per-inbox map of name -> mapped category, then intersect by name:
    // a template is kept only when present (approved) in every selected inbox.
    const perInbox = ids.map(id => {
      const map = new Map();
      approvedTemplatesFor(id).forEach(template => {
        map.set(template.name, mapTemplateCategory(template.category));
      });
      return map;
    });

    const [first, ...rest] = perInbox;
    const result = [];
    first.forEach((category, name) => {
      if (!rest.every(map => map.has(name))) return;
      // null wins: an absent category in any inbox, or disagreeing categories
      // across inboxes, makes the template uncreatable (blocked downstream).
      const categories = [category, ...rest.map(map => map.get(name))];
      const allSame = categories.every(c => c === categories[0]);
      result.push({ name, category: allSame ? categories[0] : null });
    });
    return result;
  },
  getNewConversationInboxes($state) {
    return $state.records.filter(inbox => {
      const { channel_type: channelType, phone_number: phoneNumber = '' } =
        inbox;

      const isEmailChannel = channelType === INBOX_TYPES.EMAIL;
      const isSmsChannel =
        channelType === INBOX_TYPES.TWILIO &&
        phoneNumber.startsWith('whatsapp');
      return isEmailChannel || isSmsChannel;
    });
  },
  getInbox: $state => inboxId => {
    const [inbox] = $state.records.filter(
      record => record.id === Number(inboxId)
    );
    return inbox || {};
  },
  getInboxById: $state => inboxId => {
    const [inbox] = $state.records.filter(
      record => record.id === Number(inboxId)
    );
    return camelcaseKeys(inbox || {}, { deep: true });
  },
  getUIFlags($state) {
    return $state.uiFlags;
  },
  getWebsiteInboxes($state) {
    return $state.records.filter(item => item.channel_type === INBOX_TYPES.WEB);
  },
  getTwilioInboxes($state) {
    return $state.records.filter(
      item => item.channel_type === INBOX_TYPES.TWILIO
    );
  },
  getSMSInboxes($state) {
    return $state.records.filter(
      item =>
        item.channel_type === INBOX_TYPES.SMS ||
        (item.channel_type === INBOX_TYPES.TWILIO && item.medium === 'sms')
    );
  },
  getWhatsAppInboxes($state) {
    return $state.records.filter(
      item => item.channel_type === INBOX_TYPES.WHATSAPP
    );
  },
  dialogFlowEnabledInboxes($state) {
    return $state.records.filter(
      item => item.channel_type !== INBOX_TYPES.EMAIL
    );
  },
  getFacebookInboxByInstagramId: $state => instagramId => {
    return $state.records.find(
      item =>
        item.instagram_id === instagramId &&
        item.channel_type === INBOX_TYPES.FB
    );
  },
  getInstagramInboxByInstagramId: $state => instagramId => {
    return $state.records.find(
      item =>
        item.instagram_id === instagramId &&
        item.channel_type === INBOX_TYPES.INSTAGRAM
    );
  },
  getTiktokInboxByBusinessId: $state => businessId => {
    return $state.records.find(
      item =>
        item.business_id === businessId &&
        item.channel_type === INBOX_TYPES.TIKTOK
    );
  },
};

const sendAnalyticsEvent = channelType => {
  AnalyticsHelper.track(ACCOUNT_EVENTS.ADDED_AN_INBOX, {
    channelType,
  });
};

export const actions = {
  revalidate: async ({ commit }, { newKey }) => {
    try {
      const isExistingKeyValid = await InboxesAPI.validateCacheKey(newKey);
      if (!isExistingKeyValid) {
        const response = await InboxesAPI.refetchAndCommit(newKey);
        commit(types.default.SET_INBOXES, response.data.payload);
      }
    } catch (error) {
      // Ignore error
    }
  },
  updateProviderConnection: async ({ commit }, { id, providerConnection }) => {
    commit(types.default.SET_INBOX_PROVIDER_CONNECTION, {
      id,
      providerConnection,
    });
    // Keep the local cache fresh without bumping the cache key (no full refetch).
    await InboxesAPI.updateCachedProviderConnection(id, providerConnection);
  },
  get: async ({ commit }) => {
    commit(types.default.SET_INBOXES_UI_FLAG, { isFetching: true });
    try {
      const response = await InboxesAPI.get(true);
      commit(types.default.SET_INBOXES_UI_FLAG, { isFetching: false });
      commit(types.default.SET_INBOXES, response.data.payload);
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isFetching: false });
    }
  },
  createChannel: async ({ commit }, params) => {
    try {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: true });
      const response = await WebChannel.create(params);
      commit(types.default.ADD_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      const { channel = {} } = params;
      sendAnalyticsEvent(channel.type);
      return response.data;
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      return throwErrorMessage(error);
    }
  },
  createWebsiteChannel: async ({ commit }, params) => {
    try {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: true });
      const response = await WebChannel.create(buildInboxData(params));
      commit(types.default.ADD_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      sendAnalyticsEvent('website');
      return response.data;
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      return throwErrorMessage(error);
    }
  },
  createTwilioChannel: async ({ commit }, params) => {
    try {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: true });
      const response = await TwilioChannel.create(params);
      commit(types.default.ADD_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      sendAnalyticsEvent('twilio');
      return response.data;
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      throw error;
    }
  },
  createFBChannel: async ({ commit }, params) => {
    try {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: true });
      const response = await FBChannel.create(params);
      commit(types.default.ADD_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      sendAnalyticsEvent('facebook');
      return response.data;
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      throw new Error(error);
    }
  },
  createWhatsAppEmbeddedSignup: async ({ commit }, params) => {
    try {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: true });
      const response = await WhatsappChannel.createEmbeddedSignup(params);
      commit(types.default.ADD_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      sendAnalyticsEvent('whatsapp');
      return response.data;
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      throw error;
    }
  },
  convertWhatsAppEmbeddedSignup: async ({ commit, dispatch }, params) => {
    commit(types.default.SET_INBOXES_UI_FLAG, { isUpdating: true });
    try {
      const response =
        await WhatsappChannel.postEmbeddedSignupAuthorization(params);
      await dispatch('get');
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdating: false });
      return response.data;
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdating: false });
      throw error;
    }
  },
  ...channelActions,
  // TODO: Extract other create channel methods to separate files to reduce file size
  // - createChannel
  // - createWebsiteChannel
  // - createTwilioChannel
  // - createFBChannel
  updateInbox: async ({ commit }, { id, formData = true, ...inboxParams }) => {
    commit(types.default.SET_INBOXES_UI_FLAG, { isUpdating: true });
    try {
      const response = await InboxesAPI.update(
        id,
        formData ? buildInboxData(inboxParams) : inboxParams
      );
      commit(types.default.EDIT_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdating: false });
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdating: false });
      throwErrorMessage(error);
    }
  },
  convertProvider: async (
    { commit },
    { inboxId, provider, providerConfig }
  ) => {
    commit(types.default.SET_INBOXES_UI_FLAG, { isUpdating: true });
    try {
      const response = await InboxesAPI.convertProvider(inboxId, {
        provider,
        providerConfig,
      });
      commit(types.default.EDIT_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdating: false });
      return response.data;
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdating: false });
      return throwErrorMessage(error);
    }
  },
  updateInboxIMAP: async ({ commit }, { id, ...inboxParams }) => {
    commit(types.default.SET_INBOXES_UI_FLAG, { isUpdatingIMAP: true });
    try {
      const response = await InboxesAPI.update(id, inboxParams);
      commit(types.default.EDIT_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdatingIMAP: false });
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdatingIMAP: false });
      throwErrorMessage(error);
    }
  },
  updateInboxSMTP: async ({ commit }, { id, ...inboxParams }) => {
    commit(types.default.SET_INBOXES_UI_FLAG, { isUpdatingSMTP: true });
    try {
      const response = await InboxesAPI.update(id, inboxParams);
      commit(types.default.EDIT_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdatingSMTP: false });
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdatingSMTP: false });
      throwErrorMessage(error);
    }
  },
  delete: async ({ commit }, inboxId) => {
    commit(types.default.SET_INBOXES_UI_FLAG, { isDeleting: true });
    try {
      await InboxesAPI.delete(inboxId);
      commit(types.default.DELETE_INBOXES, inboxId);
      commit(types.default.SET_INBOXES_UI_FLAG, { isDeleting: false });
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isDeleting: false });
      throw new Error(error);
    }
  },
  reauthorizeFacebookPage: async ({ commit }, params) => {
    try {
      const response = await FBChannel.reauthorizeFacebookPage(params);
      commit(types.default.EDIT_INBOXES, response.data);
    } catch (error) {
      throw new Error(error.message);
    }
  },
  deleteInboxAvatar: async (_, inboxId) => {
    try {
      await InboxesAPI.deleteInboxAvatar(inboxId);
    } catch (error) {
      throw new Error(error);
    }
  },
  syncTemplates: async ({ commit, dispatch }, inboxId) => {
    commit(types.default.SET_INBOXES_UI_FLAG, { isSyncingTemplates: true });
    try {
      await InboxesAPI.syncTemplates(inboxId);
      await dispatch('get');
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.default.SET_INBOXES_UI_FLAG, { isSyncingTemplates: false });
    }
  },
  submitTemplate: async ({ commit, dispatch }, { inboxId, payload }) => {
    commit(types.default.SET_INBOXES_UI_FLAG, { isSubmittingTemplate: true });
    try {
      const response = await InboxesAPI.submitTemplate(inboxId, payload);
      // The Meta write succeeded once the POST resolves. Refreshing the catalog
      // so the new PENDING template surfaces locally is best-effort: a transient
      // sync/refetch failure must not turn a successful submission into an error
      // (re-submitting would orphan a PENDING template — names are unique per WABA).
      try {
        await dispatch('syncTemplates', inboxId);
      } catch (syncError) {
        // Swallow: the template was already written to Meta.
      }
      return response.data;
    } catch (error) {
      const errorMessage = error?.response?.data?.error || error.message;
      throw new Error(errorMessage);
    } finally {
      commit(types.default.SET_INBOXES_UI_FLAG, {
        isSubmittingTemplate: false,
      });
    }
  },
  createCSATTemplate: async (_, { inboxId, template }) => {
    const response = await InboxesAPI.createCSATTemplate(inboxId, template);
    return response.data;
  },
  getCSATTemplateStatus: async (_, { inboxId }) => {
    const response = await InboxesAPI.getCSATTemplateStatus(inboxId);
    return response.data;
  },
  analyzeCSATTemplateUtility: async (_, { inboxId, template }) => {
    const response = await InboxesAPI.analyzeCSATTemplateUtility(
      inboxId,
      template
    );
    return response.data;
  },
  resetSecret: async ({ commit }, inboxId) => {
    try {
      const response = await InboxesAPI.resetSecret(inboxId);
      commit(types.default.EDIT_INBOXES, response.data);
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      return null;
    }
  },
  linkCSATTemplate: async (_, { inboxId, template }) => {
    const response = await InboxesAPI.linkCSATTemplate(inboxId, template);
    return response.data;
  },
  getAvailableCSATTemplates: async (_, { inboxId }) => {
    const response = await InboxesAPI.getAvailableCSATTemplates(inboxId);
    return response.data;
  },
  setupChannelProvider: async (_, inboxId) => {
    try {
      await InboxesAPI.setupChannelProvider(inboxId);
    } catch (error) {
      throwErrorMessage(error);
    }
  },
  disconnectChannelProvider: async (_, inboxId) => {
    try {
      await InboxesAPI.disconnectChannelProvider(inboxId);
    } catch (error) {
      throwErrorMessage(error);
    }
  },
};

export const mutations = {
  [types.default.SET_INBOXES_UI_FLAG]($state, uiFlag) {
    $state.uiFlags = { ...$state.uiFlags, ...uiFlag };
  },
  [types.default.SET_INBOXES]: MutationHelpers.set,
  [types.default.SET_INBOXES_ITEM]: MutationHelpers.setSingleRecord,
  [types.default.ADD_INBOXES]: MutationHelpers.create,
  [types.default.EDIT_INBOXES]: MutationHelpers.update,
  [types.default.DELETE_INBOXES]: MutationHelpers.destroy,
  [types.default.SET_INBOX_PROVIDER_CONNECTION](
    $state,
    { id, providerConnection }
  ) {
    const inbox = $state.records.find(record => record.id === Number(id));
    if (inbox) {
      inbox.provider_connection = providerConnection;
    }
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
