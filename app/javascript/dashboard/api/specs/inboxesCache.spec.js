import { describe, it, expect, vi, beforeEach } from 'vitest';
import InboxesAPI from '../inboxes';

describe('InboxesAPI cache key', () => {
  const dataManager = {
    initDb: vi.fn().mockResolvedValue(true),
    getCacheKey: vi.fn(),
    replace: vi.fn().mockResolvedValue(true),
    setCacheKeys: vi.fn().mockResolvedValue(true),
    db: true,
  };

  beforeEach(() => {
    vi.clearAllMocks();
    vi.spyOn(InboxesAPI, 'dataManager', 'get').mockReturnValue(dataManager);
  });

  // The account's cache key changes when an inbox changes, not when the payload grows a
  // field, so without the version a browser keeps serving rows written before the deploy
  // and every capability gate reads false on an inbox that supports the feature.
  it('rejects a key written before the payload version', async () => {
    dataManager.getCacheKey.mockResolvedValue('123');

    expect(await InboxesAPI.validateCacheKey('123')).toBe(false);
  });

  it('accepts a key written by this payload version', async () => {
    dataManager.getCacheKey.mockResolvedValue(
      `v${InboxesAPI.constructor.PAYLOAD_VERSION}:123`
    );

    expect(await InboxesAPI.validateCacheKey('123')).toBe(true);
  });

  it('stores the version alongside the key it refetched', async () => {
    vi.spyOn(InboxesAPI, 'getFromNetwork').mockResolvedValue({
      data: { payload: [] },
    });

    await InboxesAPI.refetchAndCommit('456');

    expect(dataManager.setCacheKeys).toHaveBeenCalledWith({
      inbox: `v${InboxesAPI.constructor.PAYLOAD_VERSION}:456`,
    });
  });
});
