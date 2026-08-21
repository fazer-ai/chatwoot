/* global axios */
import CacheEnabledApiClient from './CacheEnabledApiClient';

class Inboxes extends CacheEnabledApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  // eslint-disable-next-line class-methods-use-this
  get cacheModelName() {
    return 'inbox';
  }

  // A cached row is only usable if the build that wrote it serialized the same fields.
  // The account's cache key does not say that: it changes when an inbox changes, not when
  // the payload grows one, so after a deploy the browser keeps serving rows that predate
  // the new field and the dashboard reads absent as empty. That is how `capabilities`
  // would have hidden reactions, editing and group threads on inboxes that support them,
  // for as long as the account's inboxes happened not to change.
  //
  // Folding a version into the stored key invalidates this model alone. DATA_VERSION is
  // not the tool for it: it versions the IndexedDB schema, and it deliberately preserves
  // the keys so that adding a store does not refetch unrelated models.
  //
  // Bump on any change to the inbox payload's shape.
  static PAYLOAD_VERSION = 2;

  versionedCacheKey(cacheKey) {
    return `v${this.constructor.PAYLOAD_VERSION}:${cacheKey}`;
  }

  validateCacheKey(cacheKeyFromApi) {
    return super.validateCacheKey(this.versionedCacheKey(cacheKeyFromApi));
  }

  refetchAndCommit(newKey = null) {
    return super.refetchAndCommit(this.versionedCacheKey(newKey));
  }

  // Keeps the locally cached inbox fresh on connection-status changes without bumping
  // the cache key (so it never triggers a full refetch). Silent if IDB is unavailable.
  async updateCachedProviderConnection(id, providerConnection) {
    try {
      await this.dataManager.initDb();
      await this.dataManager.update({
        modelName: this.cacheModelName,
        id,
        data: { provider_connection: providerConnection },
      });
    } catch {
      // Ignore
    }
  }

  getCampaigns(inboxId) {
    return axios.get(`${this.url}/${inboxId}/campaigns`);
  }

  deleteInboxAvatar(inboxId) {
    return axios.delete(`${this.url}/${inboxId}/avatar`);
  }

  getAgentBot(inboxId) {
    return axios.get(`${this.url}/${inboxId}/agent_bot`);
  }

  setAgentBot(inboxId, botId) {
    return axios.post(`${this.url}/${inboxId}/set_agent_bot`, {
      agent_bot: botId,
    });
  }

  syncTemplates(inboxId) {
    return axios.post(`${this.url}/${inboxId}/sync_templates`);
  }

  getMessageTemplates(inboxId, params = {}, config = {}) {
    return axios.get(`${this.url}/${inboxId}/message_templates`, {
      ...config,
      params,
    });
  }

  updateWhatsappBusinessManagementToken(inboxId, businessManagementToken) {
    return axios.put(
      `${this.url}/${inboxId}/whatsapp_business_management_token`,
      {
        business_management_token: businessManagementToken,
      }
    );
  }

  createCSATTemplate(inboxId, template) {
    return axios.post(`${this.url}/${inboxId}/csat_template`, {
      template,
    });
  }

  getCSATTemplateStatus(inboxId) {
    return axios.get(`${this.url}/${inboxId}/csat_template`);
  }

  analyzeCSATTemplateUtility(inboxId, template) {
    return axios.post(`${this.url}/${inboxId}/csat_template/analyze`, {
      template,
    });
  }

  resetSecret(inboxId) {
    return axios.post(`${this.url}/${inboxId}/reset_secret`);
  }

  linkCSATTemplate(inboxId, template) {
    return axios.post(`${this.url}/${inboxId}/csat_template/link`, {
      template,
    });
  }

  getAvailableCSATTemplates(inboxId) {
    return axios.get(
      `${this.url}/${inboxId}/csat_template/available_templates`
    );
  }

  setupChannelProvider(inboxId) {
    return axios.post(`${this.url}/${inboxId}/setup_channel_provider`);
  }

  disconnectChannelProvider(inboxId) {
    return axios.post(`${this.url}/${inboxId}/disconnect_channel_provider`);
  }

  convertProvider(inboxId, { provider, providerConfig }) {
    return axios.post(`${this.url}/${inboxId}/convert_provider`, {
      provider,
      provider_config: providerConfig,
    });
  }

  enableWhatsappCalling(inboxId) {
    return axios.post(`${this.url}/${inboxId}/enable_whatsapp_calling`);
  }

  disableWhatsappCalling(inboxId) {
    return axios.post(`${this.url}/${inboxId}/disable_whatsapp_calling`);
  }

  setInboundCalls(inboxId, enabled) {
    return axios.post(`${this.url}/${inboxId}/set_inbound_calls`, {
      inbound_calls_enabled: enabled,
    });
  }
}

export default new Inboxes();
