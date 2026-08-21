import { describe, it, expect, vi, beforeEach } from 'vitest';
import InboxesAPI from '../inboxes';

describe('InboxesAPI cache key binding', () => {
  const dataManager = {
    initDb: vi.fn().mockResolvedValue(true),
    replace: vi.fn().mockResolvedValue(true),
    setCacheKeys: vi.fn().mockResolvedValue(true),
    db: true,
  };

  beforeEach(() => {
    vi.clearAllMocks();
    vi.spyOn(InboxesAPI, 'dataManager', 'get').mockReturnValue(dataManager);
  });

  // A rolling deploy can answer /cache_keys from the new build and this request from the
  // old one. Filing the old payload under the new key leaves it valid for good, which is
  // how an inbox keeps reporting capabilities it never received.
  it('files the rows under the key the response carried, not the one asked for', async () => {
    vi.spyOn(InboxesAPI, 'getFromNetwork').mockResolvedValue({
      data: { payload: [], cache_key: 'from-the-body' },
    });

    await InboxesAPI.refetchAndCommit('from-cache-keys');

    expect(dataManager.setCacheKeys).toHaveBeenCalledWith({
      inbox: 'from-the-body',
    });
  });

  it('falls back to the requested key when the response carries none', async () => {
    vi.spyOn(InboxesAPI, 'getFromNetwork').mockResolvedValue({
      data: { payload: [] },
    });

    await InboxesAPI.refetchAndCommit('from-cache-keys');

    expect(dataManager.setCacheKeys).toHaveBeenCalledWith({
      inbox: 'from-cache-keys',
    });
  });
});
