import axios from 'axios';
import { actions } from '../../conversationPins';
import types from '../../../mutation-types';

const commit = vi.fn();
global.axios = axios;
vi.mock('axios');

afterEach(() => {
  vi.clearAllMocks();
});

describe('#actions', () => {
  describe('#fetch', () => {
    it('replaces the pin map when the API succeeds', async () => {
      const data = [{ conversation_id: 1, pinned_at: 100 }];
      axios.get.mockResolvedValue({ data });

      await actions.fetch({ commit, state: { revision: 0 } });

      expect(commit.mock.calls).toEqual([
        [types.SET_CONVERSATION_PINS_UI_FLAG, { isFetching: true }],
        [types.SET_CONVERSATION_PINS, data],
        [types.SET_CONVERSATION_PINS_UI_FLAG, { isFetching: false }],
      ]);
    });

    it('discards a snapshot that a pin event overtook', async () => {
      // The event bumps the revision while the request is in flight, on every attempt.
      const $state = { revision: 0 };
      axios.get.mockImplementation(() => {
        $state.revision += 1;
        return Promise.resolve({
          data: [{ conversation_id: 1, pinned_at: 100 }],
        });
      });

      await actions.fetch({ commit, state: $state });

      expect(commit.mock.calls).toEqual([
        [types.SET_CONVERSATION_PINS_UI_FLAG, { isFetching: true }],
        [types.SET_CONVERSATION_PINS_UI_FLAG, { isFetching: false }],
      ]);
    });

    it('applies the snapshot on the retry when the race does not repeat', async () => {
      const $state = { revision: 0 };
      const data = [{ conversation_id: 1, pinned_at: 100 }];
      axios.get.mockImplementationOnce(() => {
        $state.revision += 1;
        return Promise.resolve({ data });
      });
      axios.get.mockImplementationOnce(() => Promise.resolve({ data }));

      await actions.fetch({ commit, state: $state });

      expect(commit.mock.calls).toEqual([
        [types.SET_CONVERSATION_PINS_UI_FLAG, { isFetching: true }],
        [types.SET_CONVERSATION_PINS, data],
        [types.SET_CONVERSATION_PINS_UI_FLAG, { isFetching: false }],
      ]);
    });

    it('keeps the inbox usable when the API fails', async () => {
      axios.get.mockRejectedValue({ message: 'Incorrect header' });

      await actions.fetch({ commit, state: { revision: 0 } });

      expect(commit.mock.calls).toEqual([
        [types.SET_CONVERSATION_PINS_UI_FLAG, { isFetching: true }],
        [types.SET_CONVERSATION_PINS_UI_FLAG, { isFetching: false }],
      ]);
    });
  });

  describe('#pin', () => {
    it('stores the pin returned by the API', async () => {
      axios.post.mockResolvedValue({
        data: { conversation_id: 1, pinned_at: 100 },
      });

      await actions.pin({ commit }, 1);

      expect(commit.mock.calls).toEqual([
        [types.SET_CONVERSATION_PIN, { conversation_id: 1, pinned_at: 100 }],
      ]);
    });

    it('throws the API error so the caller can show it', async () => {
      axios.post.mockRejectedValue({
        response: { data: { message: 'You can pin up to 5 conversations.' } },
      });

      await expect(actions.pin({ commit }, 1)).rejects.toThrow(
        'You can pin up to 5 conversations.'
      );
      expect(commit.mock.calls).toEqual([]);
    });
  });

  describe('#unpin', () => {
    it('removes the pin', async () => {
      axios.delete.mockResolvedValue({});

      await actions.unpin({ commit, state: { records: { 1: 100 } } }, 1);

      expect(commit.mock.calls).toEqual([
        [types.REMOVE_CONVERSATION_PIN, { conversation_id: 1, pinned_at: 100 }],
      ]);
    });
  });

  describe('#reset', () => {
    it('clears the account-scoped state', () => {
      actions.reset({ commit });

      expect(commit.mock.calls).toEqual([[types.CLEAR_CONVERSATION_PINS]]);
    });
  });

  describe('#add and #remove', () => {
    it('commits the websocket payload as is', () => {
      actions.add({ commit }, { conversation_id: 1, pinned_at: 100 });
      actions.remove({ commit }, { conversation_id: 1 });

      expect(commit.mock.calls).toEqual([
        [types.SET_CONVERSATION_PIN, { conversation_id: 1, pinned_at: 100 }],
        [types.REMOVE_CONVERSATION_PIN, { conversation_id: 1 }],
      ]);
    });
  });
});
