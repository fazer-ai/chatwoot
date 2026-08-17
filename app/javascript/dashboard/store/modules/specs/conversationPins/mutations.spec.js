import { mutations } from '../../conversationPins';
import types from '../../../mutation-types';

describe('#mutations', () => {
  describe('#SET_CONVERSATION_PINS', () => {
    it('replaces the whole map', () => {
      const state = { records: { 9: 1 } };
      mutations[types.SET_CONVERSATION_PINS](state, [
        { conversation_id: 1, pinned_at: 100 },
        { conversation_id: 2, pinned_at: 200 },
      ]);
      expect(state.records).toEqual({ 1: 100, 2: 200 });
    });

    it('clears the map when the payload is empty', () => {
      const state = { records: { 9: 1 } };
      mutations[types.SET_CONVERSATION_PINS](state, []);
      expect(state.records).toEqual({});
    });
  });

  describe('#SET_CONVERSATION_PIN', () => {
    it('adds a pin without dropping the others', () => {
      const state = { records: { 1: 100 } };
      mutations[types.SET_CONVERSATION_PIN](state, {
        conversation_id: 2,
        pinned_at: 200,
      });
      expect(state.records).toEqual({ 1: 100, 2: 200 });
    });
  });

  describe('#REMOVE_CONVERSATION_PIN', () => {
    it('removes a single pin', () => {
      const state = { records: { 1: 100, 2: 200 } };
      mutations[types.REMOVE_CONVERSATION_PIN](state, { conversation_id: 1 });
      expect(state.records).toEqual({ 2: 200 });
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
