import {
  SHORTCUT_KEYS,
  getTomorrowDate,
  getMondayDate,
  applyHour,
  formatShortDate,
  formatHour,
  getDatePickerLang,
  getScheduleShortcuts,
} from '../scheduleDateShortcutHelpers';

describe('#scheduleDateShortcutHelpers', () => {
  // Wednesday 2023-06-14
  const wednesday = new Date('2023-06-14T10:30:00');
  // Saturday 2023-06-17
  const saturday = new Date('2023-06-17T10:30:00');
  // Sunday 2023-06-18
  const sunday = new Date('2023-06-18T10:30:00');
  // Monday 2023-06-19
  const monday = new Date('2023-06-19T10:30:00');

  describe('getTomorrowDate', () => {
    it('returns the next day at midnight', () => {
      expect(getTomorrowDate(wednesday)).toEqual(
        new Date('2023-06-15T00:00:00')
      );
    });

    it('returns Monday from Sunday', () => {
      expect(getTomorrowDate(sunday)).toEqual(new Date('2023-06-19T00:00:00'));
    });

    it('returns Sunday from Saturday', () => {
      expect(getTomorrowDate(saturday)).toEqual(
        new Date('2023-06-18T00:00:00')
      );
    });
  });

  describe('getMondayDate', () => {
    it('returns next Monday from a weekday (Wednesday)', () => {
      expect(getMondayDate(wednesday)).toEqual(new Date('2023-06-19T00:00:00'));
    });

    it('returns next Monday from Saturday', () => {
      expect(getMondayDate(saturday)).toEqual(new Date('2023-06-19T00:00:00'));
    });

    it('returns Monday of NEXT week from Sunday (8 days away)', () => {
      // On Sunday, tomorrow is already Monday, so this returns the Monday after
      expect(getMondayDate(sunday)).toEqual(new Date('2023-06-26T00:00:00'));
    });

    it('returns next Monday from Monday (7 days away)', () => {
      expect(getMondayDate(monday)).toEqual(new Date('2023-06-26T00:00:00'));
    });
  });

  describe('applyHour', () => {
    const baseDate = new Date('2023-06-14T00:00:00');

    it('sets 8:00 for hour 8', () => {
      const result = applyHour(baseDate, 8);
      expect(result.getHours()).toBe(8);
      expect(result.getMinutes()).toBe(0);
      expect(result.getSeconds()).toBe(0);
    });

    it('sets 13:00 for hour 13', () => {
      const result = applyHour(baseDate, 13);
      expect(result.getHours()).toBe(13);
      expect(result.getMinutes()).toBe(0);
    });

    it('does not mutate the original date', () => {
      const original = new Date('2023-06-14T00:00:00');
      applyHour(original, 18);
      expect(original.getHours()).toBe(0);
    });
  });

  describe('formatShortDate', () => {
    const date = new Date('2023-03-15T00:00:00');

    it('formats with en locale', () => {
      const result = formatShortDate(date, 'en');
      expect(result).toMatch(/03.*15|15.*03/);
    });

    it('handles underscore locale tags like pt_BR', () => {
      expect(() => formatShortDate(date, 'pt_BR')).not.toThrow();
    });

    it('falls back to en for empty locale', () => {
      expect(() => formatShortDate(date, '')).not.toThrow();
    });
  });

  describe('formatHour', () => {
    it('formats 8 for en locale with AM', () => {
      const result = formatHour(8, 'en');
      expect(result).toMatch(/8.*AM/i);
    });

    it('formats 13 for en locale with PM', () => {
      const result = formatHour(13, 'en');
      expect(result).toMatch(/1.*PM/i);
    });

    it('handles underscore locale tags', () => {
      expect(() => formatHour(18, 'pt_BR')).not.toThrow();
    });
  });

  describe('getDatePickerLang', () => {
    it('returns 7 days and 12 months', () => {
      const lang = getDatePickerLang('en');
      expect(lang.days).toHaveLength(7);
      expect(lang.months).toHaveLength(12);
    });

    it('starts with Sunday', () => {
      const lang = getDatePickerLang('en');
      expect(lang.days[0]).toMatch(/Sun/i);
    });

    it('includes yearFormat and monthFormat', () => {
      const lang = getDatePickerLang('en');
      expect(lang.yearFormat).toBe('YYYY');
      expect(lang.monthFormat).toBe('MMMM');
    });

    it('handles underscore locale tags', () => {
      expect(() => getDatePickerLang('pt_BR')).not.toThrow();
    });
  });

  describe('getScheduleShortcuts', () => {
    it('returns 3 shortcuts on a normal weekday', () => {
      const shortcuts = getScheduleShortcuts(wednesday);
      expect(shortcuts).toHaveLength(3);
    });

    it('returns correct keys', () => {
      const shortcuts = getScheduleShortcuts(wednesday);
      const keys = shortcuts.map(s => s.key);
      expect(keys).toEqual([
        SHORTCUT_KEYS.TOMORROW_MORNING,
        SHORTCUT_KEYS.TOMORROW_AFTERNOON,
        SHORTCUT_KEYS.MONDAY_MORNING,
      ]);
    });

    it('computes correct dates for Wednesday', () => {
      const shortcuts = getScheduleShortcuts(wednesday);
      // Tomorrow = Thursday 2023-06-15
      expect(shortcuts[0].dateTime).toEqual(new Date('2023-06-15T08:00:00'));
      expect(shortcuts[1].dateTime).toEqual(new Date('2023-06-15T13:00:00'));
      // Monday = 2023-06-19
      expect(shortcuts[2].dateTime).toEqual(new Date('2023-06-19T08:00:00'));
    });

    it('on Sunday: tomorrow is Monday, Monday shortcut is next weeks Monday', () => {
      const shortcuts = getScheduleShortcuts(sunday);
      // Tomorrow = Monday 2023-06-19
      expect(shortcuts[0].dateTime).toEqual(new Date('2023-06-19T08:00:00'));
      expect(shortcuts[1].dateTime).toEqual(new Date('2023-06-19T13:00:00'));
      // Monday = next week's Monday 2023-06-26
      expect(shortcuts[2].dateTime).toEqual(new Date('2023-06-26T08:00:00'));
    });

    it('on Saturday: tomorrow is Sunday, Monday is the day after', () => {
      const shortcuts = getScheduleShortcuts(saturday);
      // Tomorrow = Sunday 2023-06-18
      expect(shortcuts[0].dateTime).toEqual(new Date('2023-06-18T08:00:00'));
      expect(shortcuts[1].dateTime).toEqual(new Date('2023-06-18T13:00:00'));
      // Monday = 2023-06-19
      expect(shortcuts[2].dateTime).toEqual(new Date('2023-06-19T08:00:00'));
    });

    it('on Monday: tomorrow is Tuesday, Monday shortcut is next Monday', () => {
      const shortcuts = getScheduleShortcuts(monday);
      // Tomorrow = Tuesday 2023-06-20
      expect(shortcuts[0].dateTime).toEqual(new Date('2023-06-20T08:00:00'));
      expect(shortcuts[1].dateTime).toEqual(new Date('2023-06-20T13:00:00'));
      // Monday = 2023-06-26
      expect(shortcuts[2].dateTime).toEqual(new Date('2023-06-26T08:00:00'));
    });

    it('includes formatted date and time', () => {
      const shortcuts = getScheduleShortcuts(wednesday, 'en');
      shortcuts.forEach(s => {
        expect(s.formattedDate).toBeTruthy();
        expect(s.formattedTime).toBeTruthy();
      });
    });

    it('handles pt_BR locale', () => {
      expect(() => getScheduleShortcuts(wednesday, 'pt_BR')).not.toThrow();
    });

    it('filters out shortcuts that are in the past', () => {
      // Late Wednesday night — tomorrow morning 08:00 is still in the future
      const lateWednesday = new Date('2023-06-14T23:59:00');
      const shortcuts = getScheduleShortcuts(lateWednesday);
      expect(shortcuts.length).toBeGreaterThanOrEqual(2);
      shortcuts.forEach(s => {
        expect(s.dateTime.getTime()).toBeGreaterThan(lateWednesday.getTime());
      });
    });
  });
});
