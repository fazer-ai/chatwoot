import {
  getDay,
  addDays,
  setHours,
  setMinutes,
  setSeconds,
  isBefore,
} from 'date-fns';

export const SHORTCUT_KEYS = {
  TOMORROW_MORNING: 'tomorrow_morning',
  TOMORROW_AFTERNOON: 'tomorrow_afternoon',
  MONDAY_MORNING: 'monday_morning',
  CUSTOM: 'custom',
};

/**
 * Normalize a locale tag to BCP 47 format (e.g. 'pt_BR' → 'pt-BR').
 */
const toBcp47 = locale => (locale || 'en').replace('_', '-');

/**
 * Get the date for "tomorrow" (always the next calendar day).
 */
export const getTomorrowDate = (now = new Date()) => {
  const today = new Date(now);
  today.setHours(0, 0, 0, 0);
  return addDays(today, 1);
};

/**
 * Get the date for the "Monday" shortcut.
 * On Sunday, tomorrow is already Monday, so this returns next week's Monday.
 * On all other days, returns the upcoming Monday.
 */
export const getMondayDate = (now = new Date()) => {
  const today = new Date(now);
  today.setHours(0, 0, 0, 0);
  const dayOfWeek = getDay(now); // 0=Sun, 6=Sat

  if (dayOfWeek === 0) return addDays(today, 8);
  return addDays(today, 8 - dayOfWeek);
};

/**
 * Apply an hour to a date, returning a new Date with that hour set (minutes/seconds zeroed).
 */
export const applyHour = (date, hour) =>
  setSeconds(setMinutes(setHours(new Date(date), hour), 0), 0);

/**
 * Format an hour (0-23) as a locale-aware time string (e.g. '18:00' or '6:00 PM').
 */
export const formatHour = (hour, locale = 'en') => {
  const date = new Date(2023, 0, 1, hour, 0, 0);
  return new Intl.DateTimeFormat(toBcp47(locale), {
    hour: 'numeric',
    minute: '2-digit',
  }).format(date);
};

/**
 * Format a date as a locale-aware short date with month name (e.g. '11 de mar.' / 'Mar 11').
 */
export const formatShortDate = (date, locale = 'en') =>
  new Intl.DateTimeFormat(toBcp47(locale), {
    day: 'numeric',
    month: 'short',
  }).format(date);

/**
 * Build locale-aware lang config for vue-datepicker-next.
 */
export const getDatePickerLang = (locale = 'en') => {
  const bcp47 = toBcp47(locale);
  const baseSunday = new Date(2023, 0, 1); // Sunday
  const days = Array.from({ length: 7 }, (_, i) => {
    const d = new Date(baseSunday);
    d.setDate(d.getDate() + i);
    return new Intl.DateTimeFormat(bcp47, { weekday: 'short' }).format(d);
  });

  const months = Array.from({ length: 12 }, (_, i) =>
    new Intl.DateTimeFormat(bcp47, { month: 'long' }).format(
      new Date(2023, i, 1)
    )
  );

  return { days, months, yearFormat: 'YYYY', monthFormat: 'MMMM' };
};

/**
 * Build the 3 predefined schedule shortcuts with pre-computed dates.
 * Shortcuts whose datetime is already in the past are excluded.
 */
export const getScheduleShortcuts = (now = new Date(), locale = 'en') => {
  const tomorrow = getTomorrowDate(now);
  const monday = getMondayDate(now);

  const shortcuts = [
    {
      key: SHORTCUT_KEYS.TOMORROW_MORNING,
      labelI18nKey: 'SCHEDULED_MESSAGES.MODAL.SHORTCUTS.TOMORROW_MORNING',
      date: tomorrow,
      hour: 8,
    },
    {
      key: SHORTCUT_KEYS.TOMORROW_AFTERNOON,
      labelI18nKey: 'SCHEDULED_MESSAGES.MODAL.SHORTCUTS.TOMORROW_AFTERNOON',
      date: tomorrow,
      hour: 13,
    },
    {
      key: SHORTCUT_KEYS.MONDAY_MORNING,
      labelI18nKey: 'SCHEDULED_MESSAGES.MODAL.SHORTCUTS.MONDAY_MORNING',
      date: monday,
      hour: 8,
    },
  ];

  return shortcuts
    .map(s => {
      const dateTime = applyHour(s.date, s.hour);
      const formattedDate = formatShortDate(s.date, locale);
      const formattedTime = formatHour(s.hour, locale);
      return {
        ...s,
        dateTime,
        formattedDate,
        formattedTime,
        detail: `${formattedDate}, ${formattedTime}`,
      };
    })
    .filter(s => !isBefore(s.dateTime, now));
};
