import inboxesAPI from '../inboxes';
import ApiClient from '../ApiClient';

describe('#InboxesAPI', () => {
  it('creates correct instance', () => {
    expect(inboxesAPI).toBeInstanceOf(ApiClient);
    expect(inboxesAPI).toHaveProperty('get');
    expect(inboxesAPI).toHaveProperty('show');
    expect(inboxesAPI).toHaveProperty('create');
    expect(inboxesAPI).toHaveProperty('update');
    expect(inboxesAPI).toHaveProperty('delete');
    expect(inboxesAPI).toHaveProperty('getCampaigns');
    expect(inboxesAPI).toHaveProperty('getAgentBot');
    expect(inboxesAPI).toHaveProperty('setAgentBot');
    expect(inboxesAPI).toHaveProperty('syncTemplates');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      post: vi.fn(() => Promise.resolve()),
      get: vi.fn(() => Promise.resolve()),
      patch: vi.fn(() => Promise.resolve()),
      delete: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('#getCampaigns', () => {
      inboxesAPI.getCampaigns(2);
      expect(axiosMock.get).toHaveBeenCalledWith('/api/v1/inboxes/2/campaigns');
    });

    it('#deleteInboxAvatar', () => {
      inboxesAPI.deleteInboxAvatar(2);
      expect(axiosMock.delete).toHaveBeenCalledWith('/api/v1/inboxes/2/avatar');
    });

    it('#syncTemplates', () => {
      inboxesAPI.syncTemplates(2);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/inboxes/2/sync_templates'
      );
    });
  });

  describe('#updateCachedProviderConnection', () => {
    it('patches the cached inbox record without touching the cache key', async () => {
      inboxesAPI.dataManager.initDb = vi.fn().mockResolvedValue();
      inboxesAPI.dataManager.update = vi.fn().mockResolvedValue();

      await inboxesAPI.updateCachedProviderConnection(7, {
        connection: 'open',
      });

      expect(inboxesAPI.dataManager.update).toHaveBeenCalledWith({
        modelName: 'inbox',
        id: 7,
        data: { provider_connection: { connection: 'open' } },
      });
    });

    it('swallows errors when IndexedDB is unavailable', async () => {
      inboxesAPI.dataManager.initDb = vi
        .fn()
        .mockRejectedValue(new Error('no idb'));
      inboxesAPI.dataManager.update = vi.fn();

      await expect(
        inboxesAPI.updateCachedProviderConnection(7, { connection: 'open' })
      ).resolves.toBeUndefined();
      expect(inboxesAPI.dataManager.update).not.toHaveBeenCalled();
    });
  });
});
