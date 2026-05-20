import { describe, it, expect } from 'vitest';
import { formatTimeLocalized } from '../timeFormatter';

// Translation stub used as the `t` argument. Matches the dotted key path the
// helper reads and returns the abbreviation we want to assert in the output,
// so the test focuses on bucket boundaries / unit selection without dragging
// in vue-i18n.
const stubT = key =>
  ({
    'REPORT.TIME_UNITS.SEC': 'seg',
    'REPORT.TIME_UNITS.MIN': 'min',
    'REPORT.TIME_UNITS.HR': 'h',
    'REPORT.TIME_UNITS.DAY': 'dia',
  })[key] || key;

describe('formatTimeLocalized', () => {
  it('renders seconds-only durations', () => {
    expect(formatTimeLocalized(45, stubT)).toBe('45 seg');
  });

  it('renders minutes + seconds inside the same hour', () => {
    expect(formatTimeLocalized(5 * 60 + 21, stubT)).toBe('5 min 21 seg');
  });

  it('drops the seconds when they round to zero', () => {
    expect(formatTimeLocalized(7 * 60, stubT)).toBe('7 min');
  });

  it('renders hours + minutes for durations under a day', () => {
    expect(formatTimeLocalized(5 * 3600 + 21 * 60, stubT)).toBe('5 h 21 min');
  });

  it('renders days + hours for durations over a day', () => {
    expect(formatTimeLocalized(130 * 86400 + 17 * 3600, stubT)).toBe(
      '130 dia 17 h'
    );
  });

  it('drops the hours when they round to zero', () => {
    expect(formatTimeLocalized(2 * 86400, stubT)).toBe('2 dia');
  });
});
