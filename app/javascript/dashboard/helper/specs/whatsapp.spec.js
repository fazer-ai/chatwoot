import {
  isReachoutRestricted,
  reachoutRestrictionDeadline,
  isMessageCapped,
  isMessageCapReached,
  messageCapQuota,
} from '../whatsapp';

describe('#isReachoutRestricted', () => {
  const now = new Date('2026-06-16T12:00:00.000Z').getTime();

  it('returns false when there is no lock', () => {
    expect(isReachoutRestricted(undefined, 'open', now)).toBe(false);
    expect(isReachoutRestricted(null, 'open', now)).toBe(false);
  });

  it('returns false when the lock is not active', () => {
    expect(isReachoutRestricted({ is_active: false }, 'open', now)).toBe(false);
  });

  it('returns false when the inbox is not connected (offline banner wins)', () => {
    const lock = { is_active: true };
    expect(isReachoutRestricted(lock, 'close', now)).toBe(false);
    expect(isReachoutRestricted(lock, 'connecting', now)).toBe(false);
  });

  it('returns true when active without a deadline', () => {
    expect(isReachoutRestricted({ is_active: true }, 'open', now)).toBe(true);
  });

  it('returns true when active and the deadline is in the future', () => {
    const lock = {
      is_active: true,
      time_enforcement_ends: '2026-06-19T21:52:39.000Z',
    };
    expect(isReachoutRestricted(lock, 'open', now)).toBe(true);
  });

  it('returns false when the deadline has already passed', () => {
    const lock = {
      is_active: true,
      time_enforcement_ends: '2026-06-15T21:52:39.000Z',
    };
    expect(isReachoutRestricted(lock, 'open', now)).toBe(false);
  });

  it('keeps the restriction visible when the deadline is malformed (fail safe)', () => {
    const lock = { is_active: true, time_enforcement_ends: 'not-a-date' };
    expect(isReachoutRestricted(lock, 'open', now)).toBe(true);
  });
});

describe('#reachoutRestrictionDeadline', () => {
  it('returns an empty string when there is no deadline', () => {
    expect(reachoutRestrictionDeadline(undefined)).toBe('');
    expect(reachoutRestrictionDeadline({ is_active: true })).toBe('');
  });

  it('formats the deadline as dd/MM/yyyy HH:mm', () => {
    const formatted = reachoutRestrictionDeadline({
      time_enforcement_ends: '2026-06-19T21:52:39.000Z',
    });
    expect(formatted).toMatch(/^\d{2}\/\d{2}\/\d{4} \d{2}:\d{2}$/);
  });

  it('returns an empty string when the deadline is malformed', () => {
    expect(reachoutRestrictionDeadline({ time_enforcement_ends: 'nope' })).toBe(
      ''
    );
  });
});

describe('#isMessageCapped', () => {
  it('returns false when offline regardless of status', () => {
    expect(isMessageCapped({ capping_status: 'CAPPED' }, 'connecting')).toBe(
      false
    );
  });

  it('returns false for NONE / missing / unknown status', () => {
    expect(isMessageCapped({ capping_status: 'NONE' }, 'open')).toBe(false);
    expect(isMessageCapped(undefined, 'open')).toBe(false);
    expect(isMessageCapped({}, 'open')).toBe(false);
  });

  it('returns true for warning and capped statuses when open', () => {
    expect(isMessageCapped({ capping_status: 'FIRST_WARNING' }, 'open')).toBe(
      true
    );
    expect(isMessageCapped({ capping_status: 'SECOND_WARNING' }, 'open')).toBe(
      true
    );
    expect(isMessageCapped({ capping_status: 'CAPPED' }, 'open')).toBe(true);
  });
});

describe('#isMessageCapReached', () => {
  it('is true only for CAPPED', () => {
    expect(isMessageCapReached({ capping_status: 'CAPPED' })).toBe(true);
    expect(isMessageCapReached({ capping_status: 'FIRST_WARNING' })).toBe(
      false
    );
    expect(isMessageCapReached(undefined)).toBe(false);
  });
});

describe('#messageCapQuota', () => {
  it('returns null when total_quota is missing or zero (placeholder)', () => {
    expect(messageCapQuota(undefined)).toBeNull();
    expect(messageCapQuota({ total_quota: 0, used_quota: 0 })).toBeNull();
  });

  it('returns used/total when a real quota is present', () => {
    expect(messageCapQuota({ total_quota: 100, used_quota: 80 })).toEqual({
      used: 80,
      total: 100,
    });
  });

  it('coerces string numbers and defaults missing used to 0', () => {
    expect(messageCapQuota({ total_quota: '100' })).toEqual({
      used: 0,
      total: 100,
    });
  });
});
