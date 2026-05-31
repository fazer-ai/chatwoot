import axios from 'axios';
import { actions, getters, mutations } from './disparador';
import * as types from '../mutation-types';

const commit = vi.fn();
global.axios = axios;
vi.mock('axios');

const disparo = {
  id: 1,
  name: 'June reactivation',
  status: 'draft',
  inbox_ids: [3],
};

const summary = {
  total_eligible: 12,
  total_skipped: 4,
  by_skip_reason: { missing_phone: 3, opt_out_lgpd: 1 },
  by_inbox: { 3: 12 },
  estimated_cost_cents: null,
  cost_source: 'static_table_beta0',
  snapshot_id: 'snap-1',
};

const shadowSummary = {
  total_targets: 16,
  eligible: 12,
  skipped: 4,
  created: 12,
  updated: 0,
};

const targets = [
  {
    id: 1,
    conversation_id: 10,
    contact_id: 20,
    state: 'queued',
    primary_skip_reason: null,
    phone_present: true,
  },
  {
    id: 2,
    conversation_id: 11,
    contact_id: 21,
    state: 'skipped',
    primary_skip_reason: 'missing_phone',
    phone_present: false,
  },
];

describe('disparador store', () => {
  describe('#actions', () => {
    describe('#get', () => {
      it('fetches the index and commits SET_DISPAROS', async () => {
        axios.get.mockResolvedValue({ data: [disparo] });
        const result = await actions.get({ commit });

        expect(axios.get).toHaveBeenCalledWith('/api/v1/disparos');
        expect(result).toEqual([disparo]);
        expect(commit.mock.calls).toEqual([
          [types.default.SET_DISPARADOR_UI_FLAG, { isFetching: true }],
          [types.default.SET_DISPAROS, [disparo]],
          [types.default.SET_DISPARADOR_UI_FLAG, { isFetching: false }],
        ]);
      });

      it('throws and resets flag on error', async () => {
        axios.get.mockRejectedValue({
          response: { data: { error: 'boom' } },
        });
        await expect(actions.get({ commit })).rejects.toThrow('boom');
        expect(commit.mock.calls).toEqual([
          [types.default.SET_DISPARADOR_UI_FLAG, { isFetching: true }],
          [types.default.SET_DISPARADOR_UI_FLAG, { isFetching: false }],
        ]);
      });
    });

    describe('#create', () => {
      it('wraps params under disparo and commits ADD_DISPARO on success', async () => {
        axios.post.mockResolvedValue({ data: disparo });
        const payload = { name: 'June reactivation', inbox_ids: [3] };
        const result = await actions.create({ commit }, payload);

        expect(axios.post).toHaveBeenCalledWith('/api/v1/disparos', {
          disparo: payload,
        });
        expect(result).toEqual(disparo);
        expect(commit.mock.calls).toEqual([
          [types.default.SET_DISPARADOR_UI_FLAG, { isCreating: true }],
          [types.default.ADD_DISPARO, disparo],
          [types.default.SET_DISPARADOR_UI_FLAG, { isCreating: false }],
        ]);
      });

      it('throws and resets flag on error', async () => {
        axios.post.mockRejectedValue({
          response: { data: { error: 'unsupported_inbox_provider' } },
        });
        await expect(actions.create({ commit }, {})).rejects.toThrow(
          'unsupported_inbox_provider'
        );
        expect(commit.mock.calls).toEqual([
          [types.default.SET_DISPARADOR_UI_FLAG, { isCreating: true }],
          [types.default.SET_DISPARADOR_UI_FLAG, { isCreating: false }],
        ]);
      });
    });

    describe('#show', () => {
      it('gets the disparo and commits UPDATE_DISPARO', async () => {
        axios.show = undefined;
        axios.get.mockResolvedValue({ data: disparo });
        const result = await actions.show({ commit }, 1);

        expect(axios.get).toHaveBeenCalledWith('/api/v1/disparos/1');
        expect(result).toEqual(disparo);
        expect(commit.mock.calls).toEqual([
          [types.default.SET_DISPARADOR_UI_FLAG, { isFetchingItem: true }],
          [types.default.UPDATE_DISPARO, disparo],
          [types.default.SET_DISPARADOR_UI_FLAG, { isFetchingItem: false }],
        ]);
      });
    });

    describe('#dryRun', () => {
      it('returns the summary and commits the snapshot id per disparo', async () => {
        axios.post.mockResolvedValue({ data: summary });
        const result = await actions.dryRun({ commit }, 1);

        expect(axios.post).toHaveBeenCalledWith('/api/v1/disparos/1/dry_run');
        expect(result).toEqual(summary);
        expect(commit.mock.calls).toEqual([
          [types.default.SET_DISPARADOR_UI_FLAG, { isRunningDryRun: true }],
          [types.default.SET_DISPARO_SNAPSHOT, { id: 1, snapshotId: 'snap-1' }],
          [types.default.SET_DISPARADOR_UI_FLAG, { isRunningDryRun: false }],
        ]);
      });

      it('does not commit a snapshot when the response carries none', async () => {
        axios.post.mockResolvedValue({
          data: { ...summary, snapshot_id: null },
        });
        await actions.dryRun({ commit }, 1);

        expect(commit.mock.calls).toEqual([
          [types.default.SET_DISPARADOR_UI_FLAG, { isRunningDryRun: true }],
          [types.default.SET_DISPARADOR_UI_FLAG, { isRunningDryRun: false }],
        ]);
      });

      it('throws invalid_dry_run on 422 and resets flag', async () => {
        axios.post.mockRejectedValue({
          response: { data: { error: 'invalid_dry_run' } },
        });
        await expect(actions.dryRun({ commit }, 1)).rejects.toThrow(
          'invalid_dry_run'
        );
        expect(commit.mock.calls).toEqual([
          [types.default.SET_DISPARADOR_UI_FLAG, { isRunningDryRun: true }],
          [types.default.SET_DISPARADOR_UI_FLAG, { isRunningDryRun: false }],
        ]);
      });
    });

    describe('#shadowRun', () => {
      it('posts the snapshot_id and returns the summary without storing it', async () => {
        axios.post.mockResolvedValue({ data: shadowSummary });
        const result = await actions.shadowRun(
          { commit },
          { id: 1, snapshotId: 'snap-1' }
        );

        expect(axios.post).toHaveBeenCalledWith(
          '/api/v1/disparos/1/shadow_run',
          { snapshot_id: 'snap-1' }
        );
        expect(result).toEqual(shadowSummary);
        expect(commit.mock.calls).toEqual([
          [types.default.SET_DISPARADOR_UI_FLAG, { isShadowRunning: true }],
          [types.default.SET_DISPARADOR_UI_FLAG, { isShadowRunning: false }],
        ]);
      });

      it('throws invalid_shadow_run on 422, clears the snapshot and resets flag', async () => {
        axios.post.mockRejectedValue({
          response: { data: { error: 'invalid_shadow_run' } },
        });
        await expect(
          actions.shadowRun({ commit }, { id: 1, snapshotId: 'snap-1' })
        ).rejects.toThrow('invalid_shadow_run');
        expect(commit.mock.calls).toEqual([
          [types.default.SET_DISPARADOR_UI_FLAG, { isShadowRunning: true }],
          [types.default.CLEAR_DISPARO_SNAPSHOT, 1],
          [types.default.SET_DISPARADOR_UI_FLAG, { isShadowRunning: false }],
        ]);
      });
    });

    describe('#getTargets', () => {
      it('returns the targets page and toggles the flag without storing it', async () => {
        axios.get.mockResolvedValue({ data: targets });
        const result = await actions.getTargets({ commit }, { id: 1, page: 2 });

        expect(axios.get).toHaveBeenCalledWith('/api/v1/disparos/1/targets', {
          params: { page: 2 },
        });
        expect(result).toEqual(targets);
        expect(commit.mock.calls).toEqual([
          [types.default.SET_DISPARADOR_UI_FLAG, { isFetchingTargets: true }],
          [types.default.SET_DISPARADOR_UI_FLAG, { isFetchingTargets: false }],
        ]);
      });

      it('defaults to page 1 and resets flag on error', async () => {
        axios.get.mockRejectedValue({
          response: { data: { error: 'boom' } },
        });
        await expect(actions.getTargets({ commit }, { id: 1 })).rejects.toThrow(
          'boom'
        );
        expect(axios.get).toHaveBeenCalledWith('/api/v1/disparos/1/targets', {
          params: { page: 1 },
        });
        expect(commit.mock.calls).toEqual([
          [types.default.SET_DISPARADOR_UI_FLAG, { isFetchingTargets: true }],
          [types.default.SET_DISPARADOR_UI_FLAG, { isFetchingTargets: false }],
        ]);
      });
    });
  });

  describe('#getters', () => {
    it('getDisparos returns records', () => {
      const state = { records: [disparo] };
      expect(getters.getDisparos(state)).toEqual([disparo]);
    });

    it('getUIFlags returns uiFlags', () => {
      const state = { uiFlags: { isCreating: true } };
      expect(getters.getUIFlags(state)).toEqual({ isCreating: true });
    });

    it('getSnapshotId returns the held snapshot id for a disparo', () => {
      const state = { snapshotByDisparo: { 7: 'snap-7' } };
      expect(getters.getSnapshotId(state)(7)).toBe('snap-7');
      expect(getters.getSnapshotId(state)(99)).toBeUndefined();
    });
  });

  describe('#mutations', () => {
    it('SET_DISPAROS replaces records with the fetched list', () => {
      const state = { records: [] };
      mutations[types.default.SET_DISPAROS](state, [disparo]);
      expect(state.records).toEqual([disparo]);
    });

    it('SET_DISPARADOR_UI_FLAG merges flags', () => {
      const state = { uiFlags: { isCreating: false, isRunningDryRun: false } };
      mutations[types.default.SET_DISPARADOR_UI_FLAG](state, {
        isCreating: true,
      });
      expect(state.uiFlags).toEqual({
        isCreating: true,
        isRunningDryRun: false,
      });
    });

    it('SET_DISPARO_SNAPSHOT stores the snapshot id keyed by disparo id', () => {
      const state = { snapshotByDisparo: { 1: 'snap-1' } };
      mutations[types.default.SET_DISPARO_SNAPSHOT](state, {
        id: 2,
        snapshotId: 'snap-2',
      });
      expect(state.snapshotByDisparo).toEqual({ 1: 'snap-1', 2: 'snap-2' });
    });

    it('CLEAR_DISPARO_SNAPSHOT drops only the given disparo snapshot', () => {
      const state = { snapshotByDisparo: { 1: 'snap-1', 2: 'snap-2' } };
      mutations[types.default.CLEAR_DISPARO_SNAPSHOT](state, 1);
      expect(state.snapshotByDisparo).toEqual({ 2: 'snap-2' });
    });
  });
});
