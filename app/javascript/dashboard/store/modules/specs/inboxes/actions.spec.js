import axios from 'axios';
import { actions } from '../../inboxes';
import * as types from '../../../mutation-types';
import inboxList from './fixtures';
import InboxesAPI from '../../../../api/inboxes';

const commit = vi.fn();
global.axios = axios;
vi.mock('axios');

describe('#actions', () => {
  describe('#get', () => {
    it('sends correct actions if API is success', async () => {
      const mockedGet = vi.fn(url => {
        if (url === '/api/v1/inboxes') {
          return Promise.resolve({ data: { payload: inboxList } });
        }
        if (url === '/api/v1/accounts//cache_keys') {
          return Promise.resolve({ data: { cache_keys: { inboxes: 0 } } });
        }
        // Return default value or throw an error for unexpected requests
        return Promise.reject(new Error('Unexpected request: ' + url));
      });

      axios.get = mockedGet;

      await actions.get({ commit });
      expect(commit.mock.calls).toEqual([
        [types.default.SET_INBOXES_UI_FLAG, { isFetching: true }],
        [types.default.SET_INBOXES_UI_FLAG, { isFetching: false }],
        [types.default.SET_INBOXES, inboxList],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.get.mockRejectedValue({ message: 'Incorrect header' });
      await actions.get({ commit });
      expect(commit.mock.calls).toEqual([
        [types.default.SET_INBOXES_UI_FLAG, { isFetching: true }],
        [types.default.SET_INBOXES_UI_FLAG, { isFetching: false }],
      ]);
    });
  });

  describe('#createWebsiteChannel', () => {
    it('sends correct actions if API is success', async () => {
      axios.post.mockResolvedValue({ data: inboxList[0] });
      await actions.createWebsiteChannel({ commit }, inboxList[0]);
      expect(commit.mock.calls).toEqual([
        [types.default.SET_INBOXES_UI_FLAG, { isCreating: true }],
        [types.default.ADD_INBOXES, inboxList[0]],
        [types.default.SET_INBOXES_UI_FLAG, { isCreating: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.post.mockRejectedValue({ message: 'Incorrect header' });
      await expect(actions.createWebsiteChannel({ commit })).rejects.toThrow(
        Error
      );
      expect(commit.mock.calls).toEqual([
        [types.default.SET_INBOXES_UI_FLAG, { isCreating: true }],
        [types.default.SET_INBOXES_UI_FLAG, { isCreating: false }],
      ]);
    });
  });

  describe('#createVoiceChannel', () => {
    it('sends correct actions if API is success', async () => {
      axios.post.mockResolvedValue({ data: inboxList[0] });
      await actions.createVoiceChannel({ commit }, inboxList[0]);
      expect(commit.mock.calls).toEqual([
        [types.default.SET_INBOXES_UI_FLAG, { isCreating: true }],
        [types.default.ADD_INBOXES, inboxList[0]],
        [types.default.SET_INBOXES_UI_FLAG, { isCreating: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.post.mockRejectedValue({ message: 'Incorrect header' });
      await expect(actions.createVoiceChannel({ commit })).rejects.toThrow(
        Error
      );
      expect(commit.mock.calls).toEqual([
        [types.default.SET_INBOXES_UI_FLAG, { isCreating: true }],
        [types.default.SET_INBOXES_UI_FLAG, { isCreating: false }],
      ]);
    });
  });

  describe('#createFBChannel', () => {
    it('sends correct actions if API is success', async () => {
      axios.post.mockResolvedValue({ data: inboxList[0] });
      await actions.createFBChannel({ commit }, inboxList[0]);
      expect(commit.mock.calls).toEqual([
        [types.default.SET_INBOXES_UI_FLAG, { isCreating: true }],
        [types.default.ADD_INBOXES, inboxList[0]],
        [types.default.SET_INBOXES_UI_FLAG, { isCreating: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.post.mockRejectedValue({ message: 'Incorrect header' });
      await expect(actions.createFBChannel({ commit })).rejects.toThrow(Error);
      expect(commit.mock.calls).toEqual([
        [types.default.SET_INBOXES_UI_FLAG, { isCreating: true }],
        [types.default.SET_INBOXES_UI_FLAG, { isCreating: false }],
      ]);
    });
  });

  describe('#updateInbox', () => {
    it('sends correct actions if API is success', async () => {
      const updatedInbox = inboxList[0];
      updatedInbox.enable_auto_assignment = false;

      axios.patch.mockResolvedValue({ data: updatedInbox });
      await actions.updateInbox(
        { commit },
        { id: updatedInbox.id, inbox: { enable_auto_assignment: false } }
      );
      expect(commit.mock.calls).toEqual([
        [types.default.SET_INBOXES_UI_FLAG, { isUpdating: true }],
        [types.default.EDIT_INBOXES, updatedInbox],
        [types.default.SET_INBOXES_UI_FLAG, { isUpdating: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.patch.mockRejectedValue({ message: 'Incorrect header' });
      await expect(
        actions.updateInbox(
          { commit },
          { id: inboxList[0].id, inbox: { enable_auto_assignment: false } }
        )
      ).rejects.toThrow(Error);
      expect(commit.mock.calls).toEqual([
        [types.default.SET_INBOXES_UI_FLAG, { isUpdating: true }],
        [types.default.SET_INBOXES_UI_FLAG, { isUpdating: false }],
      ]);
    });
  });

  describe('#updateInboxIMAP', () => {
    it('sends correct actions if API is success', async () => {
      const updatedInbox = inboxList[0];

      axios.patch.mockResolvedValue({ data: updatedInbox });
      await actions.updateInboxIMAP(
        { commit },
        { id: updatedInbox.id, inbox: { channel: { imap_enabled: true } } }
      );
      expect(commit.mock.calls).toEqual([
        [types.default.SET_INBOXES_UI_FLAG, { isUpdatingIMAP: true }],
        [types.default.EDIT_INBOXES, updatedInbox],
        [types.default.SET_INBOXES_UI_FLAG, { isUpdatingIMAP: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.patch.mockRejectedValue({ message: 'Incorrect header' });
      await expect(
        actions.updateInboxIMAP(
          { commit },
          { id: inboxList[0].id, inbox: { channel: { imap_enabled: true } } }
        )
      ).rejects.toThrow(Error);
      expect(commit.mock.calls).toEqual([
        [types.default.SET_INBOXES_UI_FLAG, { isUpdatingIMAP: true }],
        [types.default.SET_INBOXES_UI_FLAG, { isUpdatingIMAP: false }],
      ]);
    });
  });

  describe('#updateInboxSMTP', () => {
    it('sends correct actions if API is success', async () => {
      const updatedInbox = inboxList[0];

      axios.patch.mockResolvedValue({ data: updatedInbox });
      await actions.updateInboxSMTP(
        { commit },
        { id: updatedInbox.id, inbox: { channel: { smtp_enabled: true } } }
      );
      expect(commit.mock.calls).toEqual([
        [types.default.SET_INBOXES_UI_FLAG, { isUpdatingSMTP: true }],
        [types.default.EDIT_INBOXES, updatedInbox],
        [types.default.SET_INBOXES_UI_FLAG, { isUpdatingSMTP: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.patch.mockRejectedValue({ message: 'Incorrect header' });
      await expect(
        actions.updateInboxSMTP(
          { commit },
          { id: inboxList[0].id, inbox: { channel: { smtp_enabled: true } } }
        )
      ).rejects.toThrow(Error);
      expect(commit.mock.calls).toEqual([
        [types.default.SET_INBOXES_UI_FLAG, { isUpdatingSMTP: true }],
        [types.default.SET_INBOXES_UI_FLAG, { isUpdatingSMTP: false }],
      ]);
    });
  });

  describe('#delete', () => {
    it('sends correct actions if API is success', async () => {
      axios.delete.mockResolvedValue({ data: inboxList[0] });
      await actions.delete({ commit }, inboxList[0].id);
      expect(commit.mock.calls).toEqual([
        [types.default.SET_INBOXES_UI_FLAG, { isDeleting: true }],
        [types.default.DELETE_INBOXES, inboxList[0].id],
        [types.default.SET_INBOXES_UI_FLAG, { isDeleting: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.delete.mockRejectedValue({ message: 'Incorrect header' });
      await expect(actions.delete({ commit }, inboxList[0].id)).rejects.toThrow(
        Error
      );
      expect(commit.mock.calls).toEqual([
        [types.default.SET_INBOXES_UI_FLAG, { isDeleting: true }],
        [types.default.SET_INBOXES_UI_FLAG, { isDeleting: false }],
      ]);
    });
  });

  describe('#deleteInboxAvatar', () => {
    it('sends correct actions if API is success', async () => {
      axios.delete.mockResolvedValue();
      await expect(
        actions.deleteInboxAvatar({}, inboxList[0].id)
      ).resolves.toBe();
    });
    it('sends correct actions if API is error', async () => {
      axios.delete.mockRejectedValue({ message: 'Incorrect header' });
      await expect(
        actions.deleteInboxAvatar({}, inboxList[0].id)
      ).rejects.toThrow(Error);
    });
  });

  describe('#syncTemplates', () => {
    it('toggles uiFlag, calls API and refetches inboxes on success', async () => {
      const dispatch = vi.fn();
      axios.post.mockResolvedValue({
        data: { message: 'Template sync initiated successfully' },
      });

      await actions.syncTemplates({ commit, dispatch }, 123);

      expect(axios.post).toHaveBeenCalledWith(
        '/api/v1/inboxes/123/sync_templates'
      );
      expect(dispatch).toHaveBeenCalledWith('get');
      expect(commit.mock.calls).toEqual([
        [types.default.SET_INBOXES_UI_FLAG, { isSyncingTemplates: true }],
        [types.default.SET_INBOXES_UI_FLAG, { isSyncingTemplates: false }],
      ]);
    });

    it('toggles uiFlag off and throws error when API call fails', async () => {
      const dispatch = vi.fn();
      const errorMessage =
        'Template sync is only available for WhatsApp channels';
      axios.post.mockRejectedValue(new Error(errorMessage));

      await expect(
        actions.syncTemplates({ commit, dispatch }, 123)
      ).rejects.toThrow(errorMessage);
      expect(dispatch).not.toHaveBeenCalled();
      expect(commit.mock.calls).toEqual([
        [types.default.SET_INBOXES_UI_FLAG, { isSyncingTemplates: true }],
        [types.default.SET_INBOXES_UI_FLAG, { isSyncingTemplates: false }],
      ]);
    });
  });

  describe('#submitTemplate', () => {
    const payload = {
      name: 'order_update',
      language: 'pt_BR',
      category: 'UTILITY',
      components: [{ type: 'BODY', text: 'Hello {{1}}' }],
    };

    it('toggles uiFlag, posts the template and triggers a sync on success', async () => {
      const dispatch = vi.fn();
      axios.post.mockResolvedValue({
        data: { template_id: 'abc123', status: 'PENDING' },
      });

      const result = await actions.submitTemplate(
        { commit, dispatch },
        { inboxId: 123, payload }
      );

      expect(axios.post).toHaveBeenCalledWith(
        '/api/v1/inboxes/123/submit_template',
        { template: payload }
      );
      expect(dispatch).toHaveBeenCalledWith('syncTemplates', 123);
      expect(result).toEqual({ template_id: 'abc123', status: 'PENDING' });
      expect(commit.mock.calls).toEqual([
        [types.default.SET_INBOXES_UI_FLAG, { isSubmittingTemplate: true }],
        [types.default.SET_INBOXES_UI_FLAG, { isSubmittingTemplate: false }],
      ]);
    });

    it('resolves with the Meta write result even when the post-write refresh fails', async () => {
      const dispatch = vi.fn().mockRejectedValue(new Error('sync down'));
      axios.post.mockResolvedValue({
        data: { template_id: 'abc123', status: 'PENDING' },
      });

      const result = await actions.submitTemplate(
        { commit, dispatch },
        { inboxId: 123, payload }
      );

      expect(dispatch).toHaveBeenCalledWith('syncTemplates', 123);
      expect(result).toEqual({ template_id: 'abc123', status: 'PENDING' });
      expect(commit.mock.calls).toEqual([
        [types.default.SET_INBOXES_UI_FLAG, { isSubmittingTemplate: true }],
        [types.default.SET_INBOXES_UI_FLAG, { isSubmittingTemplate: false }],
      ]);
    });

    it('toggles uiFlag off and throws the Meta error message on 422', async () => {
      const dispatch = vi.fn();
      axios.post.mockRejectedValue({
        response: { data: { error: 'Template name already exists' } },
      });

      await expect(
        actions.submitTemplate({ commit, dispatch }, { inboxId: 123, payload })
      ).rejects.toThrow('Template name already exists');
      expect(dispatch).not.toHaveBeenCalled();
      expect(commit.mock.calls).toEqual([
        [types.default.SET_INBOXES_UI_FLAG, { isSubmittingTemplate: true }],
        [types.default.SET_INBOXES_UI_FLAG, { isSubmittingTemplate: false }],
      ]);
    });
  });

  describe('#updateProviderConnection', () => {
    it('commits the targeted mutation and patches the local cache', async () => {
      const cacheSpy = vi
        .spyOn(InboxesAPI, 'updateCachedProviderConnection')
        .mockResolvedValue();
      const providerConnection = { connection: 'open' };

      await actions.updateProviderConnection(
        { commit },
        { id: 7, providerConnection }
      );

      expect(commit).toHaveBeenCalledWith(
        types.default.SET_INBOX_PROVIDER_CONNECTION,
        { id: 7, providerConnection }
      );
      expect(cacheSpy).toHaveBeenCalledWith(7, providerConnection);
    });
  });
});
