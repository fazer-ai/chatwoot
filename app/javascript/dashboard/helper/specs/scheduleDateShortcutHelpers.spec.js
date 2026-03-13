import {
  SCHEDULE_DAY_OPTIONS,
  SCHEDULE_TIME_PERIODS,
  TIME_PERIOD_HOURS,
  getShortcutDate,
  applyTimePeriod,
  isTimePeriodPast,
  formatShortDate,
  formatHour,
  getDatePickerLang,
  getDayShortcutOptions,
} from '../scheduleDateShortcutHelpers';

describe('#scheduleDateShortcutHelpers', () => {
  // Wednesday 2023-06-14
  const wednesday = new Date('2023-06-14T10:30:00');
  // Saturday 2023-06-17
  const saturday = new Date('2023-06-17T10:30:00');
  // Sunday 2023-06-18
  const sunday = new Date('2023-06-18T10:30:00');

  describe('getShortcutDate', () => {
    it('returns today at midnight for TODAY', () => {
      const result = getShortcutDate(SCHEDULE_DAY_OPTIONS.TODAY, wednesday);
      expect(result).toEqual(new Date('2023-06-14T00:00:00'));
    });

    it('returns tomorrow at midnight for TOMORROW', () => {
      const result = getShortcutDate(SCHEDULE_DAY_OPTIONS.TOMORROW, wednesday);
      expect(result).toEqual(new Date('2023-06-15T00:00:00'));
    });

    describe('THIS_WEEKEND', () => {
      it('returns next Saturday from a weekday', () => {
        const result = getShortcutDate(
          SCHEDULE_DAY_OPTIONS.THIS_WEEKEND,
          wednesday
        );
        expect(result).toEqual(new Date('2023-06-17T00:00:00'));
      });

      it('returns today when already Saturday', () => {
        const result = getShortcutDate(
          SCHEDULE_DAY_OPTIONS.THIS_WEEKEND,
          saturday
        );
        expect(result).toEqual(new Date('2023-06-17T00:00:00'));
      });

      it('returns next Saturday from Sunday', () => {
        const result = getShortcutDate(
          SCHEDULE_DAY_OPTIONS.THIS_WEEKEND,
          sunday
        );
        expect(result).toEqual(new Date('2023-06-24T00:00:00'));
      });
    });

    describe('NEXT_WEEK', () => {
      it('returns next Monday from a weekday', () => {
        const result = getShortcutDate(
          SCHEDULE_DAY_OPTIONS.NEXT_WEEK,
          wednesday
        );
        expect(result).toEqual(new Date('2023-06-19T00:00:00'));
      });

      it('returns next Monday from Sunday', () => {
        const result = getShortcutDate(SCHEDULE_DAY_OPTIONS.NEXT_WEEK, sunday);
        expect(result).toEqual(new Date('2023-06-19T00:00:00'));
      });

      it('returns next Monday from Saturday', () => {
        const result = getShortcutDate(
          SCHEDULE_DAY_OPTIONS.NEXT_WEEK,
          saturday
        );
        expect(result).toEqual(new Date('2023-06-19T00:00:00'));
      });
    });

    describe('NEXT_WEEKEND', () => {
      it('returns next-next Saturday from a weekday', () => {
        const result = getShortcutDate(
          SCHEDULE_DAY_OPTIONS.NEXT_WEEKEND,
          wednesday
        );
        expect(result).toEqual(new Date('2023-06-24T00:00:00'));
      });

      it('returns next Saturday from Saturday', () => {
        const result = getShortcutDate(
          SCHEDULE_DAY_OPTIONS.NEXT_WEEKEND,
          saturday
        );
        expect(result).toEqual(new Date('2023-06-24T00:00:00'));
      });

      it('returns Saturday 13 days later from Sunday', () => {
        const result = getShortcutDate(
          SCHEDULE_DAY_OPTIONS.NEXT_WEEKEND,
          sunday
        );
        expect(result).toEqual(new Date('2023-07-01T00:00:00'));
      });
    });

    it('returns first day of next month for NEXT_MONTH', () => {
      const result = getShortcutDate(
        SCHEDULE_DAY_OPTIONS.NEXT_MONTH,
        wednesday
      );
      expect(result).toEqual(new Date('2023-07-01T00:00:00'));
    });

    it('returns today for unknown key', () => {
      const result = getShortcutDate('unknown', wednesday);
      expect(result).toEqual(new Date('2023-06-14T00:00:00'));
    });
  });

  describe('applyTimePeriod', () => {
    const baseDate = new Date('2023-06-14T00:00:00');

    it('sets 8:00 for morning', () => {
      const result = applyTimePeriod(baseDate, SCHEDULE_TIME_PERIODS.MORNING);
      expect(result.getHours()).toBe(8);
      expect(result.getMinutes()).toBe(0);
      expect(result.getSeconds()).toBe(0);
    });

    it('sets 13:00 for afternoon', () => {
      const result = applyTimePeriod(baseDate, SCHEDULE_TIME_PERIODS.AFTERNOON);
      expect(result.getHours()).toBe(13);
      expect(result.getMinutes()).toBe(0);
    });

    it('sets 18:00 for evening', () => {
      const result = applyTimePeriod(baseDate, SCHEDULE_TIME_PERIODS.EVENING);
      expect(result.getHours()).toBe(18);
      expect(result.getMinutes()).toBe(0);
    });

    it('defaults to 8:00 for unknown period', () => {
      const result = applyTimePeriod(baseDate, 'unknown');
      expect(result.getHours()).toBe(8);
    });

    it('does not mutate the original date', () => {
      const original = new Date('2023-06-14T00:00:00');
      applyTimePeriod(original, SCHEDULE_TIME_PERIODS.EVENING);
      expect(original.getHours()).toBe(0);
    });
  });

  describe('isTimePeriodPast', () => {
    it('returns true when the time period is in the past', () => {
      const today = new Date('2023-06-14T00:00:00');
      const now = new Date('2023-06-14T14:00:00');
      expect(isTimePeriodPast(today, SCHEDULE_TIME_PERIODS.MORNING, now))
        .toBe()
        .toBe(true);
    });

    it('returns false when the time period is in the future', () => {
      const today = new Date('2023-06-14T00:00:00');
      const now = new Date('2023-06-14T07:00:00');
      expect(isTimePeriodPast(today, SCHEDULE_TIME_PERIODS.MORNING, now)).toBe(
        false
      );
    });

    it('returns true for all periods late at night', () => {
      const today = new Date('2023-06-14T00:00:00');
      const now = new Date('2023-06-14T23:00:00');
      expect(isTimePeriodPast(today, SCHEDULE_TIME_PERIODS.EVENING, now)).toBe(
        true
      );
    });

    it('returns false for future dates regardless of time', () => {
      const tomorrow = new Date('2023-06-15T00:00:00');
      const now = new Date('2023-06-14T23:00:00');
      expect(
        isTimePeriodPast(tomorrow, SCHEDULE_TIME_PERIODS.MORNING, now)
      ).toBe(false);
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

  describe('getDayShortcutOptions', () => {
    it('returns 7 options (6 shortcuts + custom)', () => {
      const options = getDayShortcutOptions(wednesday);
      expect(options).toHaveLength(7);
    });

    it('includes all day option keys', () => {
      const options = getDayShortcutOptions(wednesday);
      const keys = options.map(o => o.key);
      expect(keys).toEqual([
        SCHEDULE_DAY_OPTIONS.TODAY,
        SCHEDULE_DAY_OPTIONS.TOMORROW,
        SCHEDULE_DAY_OPTIONS.THIS_WEEKEND,
        SCHEDULE_DAY_OPTIONS.NEXT_WEEK,
        SCHEDULE_DAY_OPTIONS.NEXT_WEEKEND,
        SCHEDULE_DAY_OPTIONS.NEXT_MONTH,
        SCHEDULE_DAY_OPTIONS.CUSTOM,
      ]);
    });

    it('sets formattedDate for non-custom options', () => {
      const options = getDayShortcutOptions(wednesday);
      options
        .filter(o => o.key !== SCHEDULE_DAY_OPTIONS.CUSTOM)
        .forEach(o => {
          expect(o.formattedDate).toBeTruthy();
          expect(o.date).toBeInstanceOf(Date);
        });
    });

    it('sets null date and formattedDate for custom option', () => {
      const options = getDayShortcutOptions(wednesday);
      const custom = options.find(o => o.key === SCHEDULE_DAY_OPTIONS.CUSTOM);
      expect(custom.date).toBeNull();
      expect(custom.formattedDate).toBeNull();
    });

    it('passes locale to formatShortDate', () => {
      expect(() => getDayShortcutOptions(wednesday, 'pt_BR')).not.toThrow();
    });
  });

  describe('TIME_PERIOD_HOURS', () => {
    it('maps morning to 8', () => {
      expect(TIME_PERIOD_HOURS[SCHEDULE_TIME_PERIODS.MORNING]).toBe(8);
    });

    it('maps afternoon to 13', () => {
      expect(TIME_PERIOD_HOURS[SCHEDULE_TIME_PERIODS.AFTERNOON]).toBe(13);
    });

    it('maps evening to 18', () => {
      expect(TIME_PERIOD_HOURS[SCHEDULE_TIME_PERIODS.EVENING]).toBe(18);
    });
  });
});
