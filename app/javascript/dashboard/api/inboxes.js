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
}

export default new Inboxes();
