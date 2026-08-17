import { mutations } from '../../conversationPins';
import types from '../../../mutation-types';

describe('#mutations', () => {
  describe('#SET_CONVERSATION_PINS', () => {
    it('replaces the whole map', () => {
      const state = { records: { 9: 1 }, appliedAt: {} };
      mutations[types.SET_CONVERSATION_PINS](state, {
        synced_at: 1000,
        pins: [
          { conversation_id: 1, pinned_at: 100 },
          { conversation_id: 2, pinned_at: 200 },
        ],
      });
      expect(state.records).toEqual({ 1: 100, 2: 200 });
    });

    it('clears the map when the payload is empty', () => {
      const state = { records: { 9: 1 }, appliedAt: {} };
      mutations[types.SET_CONVERSATION_PINS](state, {
        synced_at: 1000,
        pins: [],
      });
      expect(state.records).toEqual({});
    });
  });

  describe('#SET_CONVERSATION_PIN', () => {
    it('adds a pin without dropping the others', () => {
      const state = { records: { 1: 100 }, appliedAt: {} };
      mutations[types.SET_CONVERSATION_PIN](state, {
        conversation_id: 2,
        pinned_at: 200,
      });
      expect(state.records).toEqual({ 1: 100, 2: 200 });
    });
  });

  describe('#REMOVE_CONVERSATION_PIN', () => {
    it('removes a single pin', () => {
      const state = { records: { 1: 100, 2: 200 }, appliedAt: {} };
      mutations[types.REMOVE_CONVERSATION_PIN](state, { conversation_id: 1 });
      expect(state.records).toEqual({ 2: 200 });
    });
  });

  describe('out-of-order websocket events', () => {
    it('ignores a pinned event that lost the race with the unpin after it', () => {
      const state = { records: {}, appliedAt: {} };
      // The unpin broadcast wins the race, so the pin it removed arrives afterwards.
      mutations[types.REMOVE_CONVERSATION_PIN](state, {
        conversation_id: 1,
        pinned_at: 100,
      });
      mutations[types.SET_CONVERSATION_PIN](state, {
        conversation_id: 1,
        pinned_at: 100,
      });

      expect(state.records).toEqual({});
    });

    it('ignores an unpin event older than the pin already applied', () => {
      const state = { records: {}, appliedAt: {} };
      mutations[types.SET_CONVERSATION_PIN](state, {
        conversation_id: 1,
        pinned_at: 200,
      });
      mutations[types.REMOVE_CONVERSATION_PIN](state, {
        conversation_id: 1,
        pinned_at: 100,
      });

      expect(state.records).toEqual({ 1: 200 });
    });

    it('applies a pin created after the last event', () => {
      const state = { records: {}, appliedAt: {} };
      mutations[types.REMOVE_CONVERSATION_PIN](state, {
        conversation_id: 1,
        pinned_at: 100,
      });
      mutations[types.SET_CONVERSATION_PIN](state, {
        conversation_id: 1,
        pinned_at: 200,
      });

      expect(state.records).toEqual({ 1: 200 });
    });

    it('keeps a pin the snapshot could not have seen', () => {
      const state = { records: {}, appliedAt: {} };
      mutations[types.SET_CONVERSATION_PIN](state, {
        conversation_id: 1,
        pinned_at: 1500,
      });
      // Snapshot built before the pin landed.
      mutations[types.SET_CONVERSATION_PINS](state, {
        synced_at: 1000,
        pins: [],
      });

      expect(state.records).toEqual({ 1: 1500 });
    });

    it('does not let a snapshot resurrect a pin removed after it was built', () => {
      const state = { records: { 1: 900 }, appliedAt: { 1: 900 } };
      mutations[types.REMOVE_CONVERSATION_PIN](state, {
        conversation_id: 1,
        pinned_at: 1500,
      });
      mutations[types.SET_CONVERSATION_PINS](state, {
        synced_at: 1000,
        pins: [{ conversation_id: 1, pinned_at: 900 }],
      });

      expect(state.records).toEqual({});
    });

    it('trusts the snapshot for events it already covers', () => {
      const state = { records: {}, appliedAt: { 1: 500 } };
      mutations[types.SET_CONVERSATION_PINS](state, {
        synced_at: 1000,
        pins: [{ conversation_id: 1, pinned_at: 500 }],
      });

      expect(state.records).toEqual({ 1: 500 });
    });

    it('ignores a pin event older than the pin currently held', () => {
      const state = { records: {}, appliedAt: {} };
      // pin -> unpin -> re-pin, with the first pin's broadcast arriving last.
      mutations[types.SET_CONVERSATION_PIN](state, {
        conversation_id: 1,
        pinned_at: 200,
      });
      mutations[types.SET_CONVERSATION_PIN](state, {
        conversation_id: 1,
        pinned_at: 100,
      });

      expect(state.records).toEqual({ 1: 200 });
      expect(state.appliedAt).toEqual({ 1: 200 });
    });

    it('does not let a stale unpin remove the pin that replaced it', () => {
      const state = { records: {}, appliedAt: {} };
      mutations[types.SET_CONVERSATION_PIN](state, {
        conversation_id: 1,
        pinned_at: 200,
      });
      mutations[types.SET_CONVERSATION_PIN](state, {
        conversation_id: 1,
        pinned_at: 100,
      });
      mutations[types.REMOVE_CONVERSATION_PIN](state, {
        conversation_id: 1,
        pinned_at: 100,
      });

      expect(state.records).toEqual({ 1: 200 });
    });

    it('keeps the versions of unpinned conversations across a hydration', () => {
      const state = { records: {}, appliedAt: {} };
      mutations[types.REMOVE_CONVERSATION_PIN](state, {
        conversation_id: 1,
        pinned_at: 100,
      });
      mutations[types.SET_CONVERSATION_PINS](state, {
        synced_at: 1000,
        pins: [{ conversation_id: 2, pinned_at: 300 }],
      });
      mutations[types.SET_CONVERSATION_PIN](state, {
        conversation_id: 1,
        pinned_at: 100,
      });

      expect(state.records).toEqual({ 2: 300 });
    });
  });

  describe('#SET_CONVERSATION_PINS_UI_FLAG', () => {
    it('merges the flags', () => {
      const state = { uiFlags: { isFetching: false } };
      mutations[types.SET_CONVERSATION_PINS_UI_FLAG](state, {
        isFetching: true,
      });
      expect(state.uiFlags).toEqual({ isFetching: true });
    });
  });
});
