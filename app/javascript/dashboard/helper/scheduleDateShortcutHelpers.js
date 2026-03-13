import {
  getDay,
  addDays,
  startOfMonth,
  addMonths,
  setHours,
  setMinutes,
  setSeconds,
  isBefore,
} from 'date-fns';

export const SCHEDULE_DAY_OPTIONS = {
  TODAY: 'today',
  TOMORROW: 'tomorrow',
  THIS_WEEKEND: 'this_weekend',
  NEXT_WEEK: 'next_week',
  NEXT_WEEKEND: 'next_weekend',
  NEXT_MONTH: 'next_month',
  CUSTOM: 'custom',
};

export const SCHEDULE_TIME_PERIODS = {
  MORNING: 'morning',
  AFTERNOON: 'afternoon',
  EVENING: 'evening',
};

export const TIME_PERIOD_HOURS = {
  [SCHEDULE_TIME_PERIODS.MORNING]: 8,
  [SCHEDULE_TIME_PERIODS.AFTERNOON]: 13,
  [SCHEDULE_TIME_PERIODS.EVENING]: 18,
};

/**
 * Get the target date for a day shortcut (date only, at midnight).
 */
export const getShortcutDate = (dayKey, now = new Date()) => {
  const today = new Date(now);
  today.setHours(0, 0, 0, 0);
  const dayOfWeek = getDay(now); // 0=Sun, 6=Sat

  switch (dayKey) {
    case SCHEDULE_DAY_OPTIONS.TODAY:
      return today;

    case SCHEDULE_DAY_OPTIONS.TOMORROW:
      return addDays(today, 1);

    case SCHEDULE_DAY_OPTIONS.THIS_WEEKEND:
      if (dayOfWeek === 6) return today;
      if (dayOfWeek === 0) return addDays(today, 6);
      return addDays(today, 6 - dayOfWeek);

    case SCHEDULE_DAY_OPTIONS.NEXT_WEEK:
      if (dayOfWeek === 0) return addDays(today, 1);
      return addDays(today, 8 - dayOfWeek);

    case SCHEDULE_DAY_OPTIONS.NEXT_WEEKEND:
      if (dayOfWeek === 6) return addDays(today, 7);
      if (dayOfWeek === 0) return addDays(today, 13);
      return addDays(today, 13 - dayOfWeek);

    case SCHEDULE_DAY_OPTIONS.NEXT_MONTH:
      return startOfMonth(addMonths(today, 1));

    default:
      return today;
  }
};

/**
 * Apply a time period to a date, returning a Date with hours set.
 */
export const applyTimePeriod = (date, timePeriod) => {
  const hours = TIME_PERIOD_HOURS[timePeriod] ?? 8;
  return setSeconds(setMinutes(setHours(new Date(date), hours), 0), 0);
};

/**
 * Check if a time period would result in a past datetime for a given day.
 */
export const isTimePeriodPast = (date, timePeriod, now = new Date()) => {
  const target = applyTimePeriod(date, timePeriod);
  return isBefore(target, now);
};

/**
 * Format a date as a locale-aware short date (day/month) for display in labels.
 * @param {Date} date
 * @param {string} locale - BCP 47 locale tag (e.g. 'en', 'pt-BR')
 */
export const formatShortDate = (date, locale = 'en') =>
  new Intl.DateTimeFormat(locale, {
    day: '2-digit',
    month: '2-digit',
  }).format(date);

/**
 * Build locale-aware lang config for vue-datepicker-next.
 * Uses Intl.DateTimeFormat to generate day/month names for the given locale.
 */
export const getDatePickerLang = (locale = 'en') => {
  const baseSunday = new Date(2023, 0, 1); // Sunday
  const days = Array.from({ length: 7 }, (_, i) => {
    const d = new Date(baseSunday);
    d.setDate(d.getDate() + i);
    return new Intl.DateTimeFormat(locale, { weekday: 'short' }).format(d);
  });

  const months = Array.from({ length: 12 }, (_, i) =>
    new Intl.DateTimeFormat(locale, { month: 'long' }).format(
      new Date(2023, i, 1)
    )
  );

  return { days, months, yearFormat: 'YYYY', monthFormat: 'MMMM' };
};

/**
 * Build the list of day shortcut options with computed dates.
 */
export const getDayShortcutOptions = (now = new Date(), locale = 'en') => {
  const options = [
    {
      key: SCHEDULE_DAY_OPTIONS.TODAY,
      labelI18nKey: 'SCHEDULED_MESSAGES.MODAL.SHORTCUTS.DAYS.TODAY',
    },
    {
      key: SCHEDULE_DAY_OPTIONS.TOMORROW,
      labelI18nKey: 'SCHEDULED_MESSAGES.MODAL.SHORTCUTS.DAYS.TOMORROW',
    },
    {
      key: SCHEDULE_DAY_OPTIONS.THIS_WEEKEND,
      labelI18nKey: 'SCHEDULED_MESSAGES.MODAL.SHORTCUTS.DAYS.THIS_WEEKEND',
    },
    {
      key: SCHEDULE_DAY_OPTIONS.NEXT_WEEK,
      labelI18nKey: 'SCHEDULED_MESSAGES.MODAL.SHORTCUTS.DAYS.NEXT_WEEK',
    },
    {
      key: SCHEDULE_DAY_OPTIONS.NEXT_WEEKEND,
      labelI18nKey: 'SCHEDULED_MESSAGES.MODAL.SHORTCUTS.DAYS.NEXT_WEEKEND',
    },
    {
      key: SCHEDULE_DAY_OPTIONS.NEXT_MONTH,
      labelI18nKey: 'SCHEDULED_MESSAGES.MODAL.SHORTCUTS.DAYS.NEXT_MONTH',
    },
    {
      key: SCHEDULE_DAY_OPTIONS.CUSTOM,
      labelI18nKey: 'SCHEDULED_MESSAGES.MODAL.SHORTCUTS.DAYS.CUSTOM',
    },
  ];

  return options.map(option => {
    if (option.key === SCHEDULE_DAY_OPTIONS.CUSTOM) {
      return { ...option, date: null, formattedDate: null };
    }
    const date = getShortcutDate(option.key, now);
    return { ...option, date, formattedDate: formatShortDate(date, locale) };
  });
};
