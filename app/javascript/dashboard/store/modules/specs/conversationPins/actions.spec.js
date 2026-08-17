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
      axios.get.mockResolvedValue({
        data: [{ conversation_id: 1, pinned_at: 100 }],
      });

      await actions.fetch({ commit });

      expect(commit.mock.calls).toEqual([
        [types.SET_CONVERSATION_PINS_UI_FLAG, { isFetching: true }],
        [types.SET_CONVERSATION_PINS, [{ conversation_id: 1, pinned_at: 100 }]],
        [types.SET_CONVERSATION_PINS_UI_FLAG, { isFetching: false }],
      ]);
    });

    it('keeps the inbox usable when the API fails', async () => {
      axios.get.mockRejectedValue({ message: 'Incorrect header' });

      await actions.fetch({ commit });

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
