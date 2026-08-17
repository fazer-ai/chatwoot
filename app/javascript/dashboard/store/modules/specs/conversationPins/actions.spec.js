import axios from 'axios';
import { actions } from '../../conversationPins';
import types from '../../../mutation-types';

const commit = vi.fn();
const rootGetters = { getCurrentAccountId: 1 };
global.axios = axios;
vi.mock('axios');

afterEach(() => {
  vi.clearAllMocks();
});

describe('#actions', () => {
  describe('#fetch', () => {
    it('applies the snapshot when nothing changed under it', async () => {
      const data = [{ conversation_id: 1, pinned_at: 100 }];
      axios.get.mockResolvedValue({ data });

      await actions.fetch({
        commit,
        rootGetters,
        state: { revision: 0, appliedAt: {}, records: {} },
      });

      expect(commit.mock.calls).toEqual([
        [types.SET_CONVERSATION_PINS_UI_FLAG, { isFetching: true }],
        [
          types.SET_CONVERSATION_PINS,
          { pins: data, appliedAtBefore: {}, recordsBefore: {} },
        ],
        [types.SET_CONVERSATION_PINS_UI_FLAG, { isFetching: false }],
      ]);
    });

    it('hands the mutation the versions and the map it started from, so events under it win', async () => {
      const $state = {
        revision: 0,
        appliedAt: { 1: 100 },
        records: { 1: 100 },
      };
      const data = [{ conversation_id: 1, pinned_at: 100 }];
      axios.get.mockImplementation(() => {
        // An unpin lands while the request is in flight. It keeps the pin's own version, so only the map
        // it left behind tells the mutation that anything moved.
        $state.records = {};
        return Promise.resolve({ data });
      });

      await actions.fetch({ commit, rootGetters, state: $state });

      expect(commit.mock.calls).toEqual([
        [types.SET_CONVERSATION_PINS_UI_FLAG, { isFetching: true }],
        [
          types.SET_CONVERSATION_PINS,
          {
            pins: data,
            appliedAtBefore: { 1: 100 },
            recordsBefore: { 1: 100 },
          },
        ],
        [types.SET_CONVERSATION_PINS_UI_FLAG, { isFetching: false }],
      ]);
    });

    it('discards a snapshot that another hydration already replaced', async () => {
      const $state = { revision: 0, appliedAt: {} };
      axios.get.mockImplementation(() => {
        $state.revision += 1;
        return Promise.resolve({
          data: [{ conversation_id: 1, pinned_at: 100 }],
        });
      });

      await actions.fetch({ commit, rootGetters, state: $state });

      expect(commit.mock.calls).toEqual([
        [types.SET_CONVERSATION_PINS_UI_FLAG, { isFetching: true }],
        [types.SET_CONVERSATION_PINS_UI_FLAG, { isFetching: false }],
      ]);
    });

    it('discards a snapshot that outlived the account it was made in', async () => {
      const movingRootGetters = { getCurrentAccountId: 1 };
      axios.get.mockImplementation(() => {
        movingRootGetters.getCurrentAccountId = 2;
        return Promise.resolve({
          data: [{ conversation_id: 1, pinned_at: 100 }],
        });
      });

      await actions.fetch({
        commit,
        rootGetters: movingRootGetters,
        state: { revision: 0, appliedAt: {} },
      });

      expect(commit.mock.calls).toEqual([
        [types.SET_CONVERSATION_PINS_UI_FLAG, { isFetching: true }],
        [types.SET_CONVERSATION_PINS_UI_FLAG, { isFetching: false }],
      ]);
    });

    it('keeps the inbox usable when the API fails', async () => {
      axios.get.mockRejectedValue({ message: 'Incorrect header' });

      await actions.fetch({
        commit,
        rootGetters,
        state: { revision: 0, appliedAt: {} },
      });

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

      await actions.pin({ commit, rootGetters }, 1);

      expect(commit.mock.calls).toEqual([
        [types.SET_CONVERSATION_PIN, { conversation_id: 1, pinned_at: 100 }],
      ]);
    });

    it('throws the API error so the caller can show it', async () => {
      axios.post.mockRejectedValue({
        response: { data: { message: 'You can pin up to 5 conversations.' } },
      });

      await expect(actions.pin({ commit, rootGetters }, 1)).rejects.toThrow(
        'You can pin up to 5 conversations.'
      );
      expect(commit.mock.calls).toEqual([]);
    });

    it('drops a response that outlived the account it was made in', async () => {
      const movingRootGetters = { getCurrentAccountId: 1 };
      axios.post.mockImplementation(() => {
        movingRootGetters.getCurrentAccountId = 2;
        return Promise.resolve({
          data: { conversation_id: 1, pinned_at: 100 },
        });
      });

      await actions.pin({ commit, rootGetters: movingRootGetters }, 1);

      expect(commit.mock.calls).toEqual([]);
    });
  });

  describe('#unpin', () => {
    it('removes the pin', async () => {
      axios.delete.mockResolvedValue({});

      await actions.unpin(
        { commit, rootGetters, state: { records: { 1: 100 } } },
        1
      );

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
