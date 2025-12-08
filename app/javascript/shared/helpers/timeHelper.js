import {
  format,
  isSameYear,
  fromUnixTime,
  formatDistanceToNow,
  differenceInDays,
  differenceInMinutes,
  differenceInHours,
  differenceInMonths,
  differenceInYears,
  differenceInSeconds,
} from 'date-fns';

/**
 * Formats a Unix timestamp into a human-readable time format.
 * @param {number} time - Unix timestamp.
 * @param {string} [dateFormat='h:mm a'] - Desired format of the time.
 * @returns {string} Formatted time string.
 */
export const messageStamp = (time, dateFormat = 'h:mm a') => {
  const unixTime = fromUnixTime(time);
  return format(unixTime, dateFormat);
};

/**
 * Provides a formatted timestamp, adjusting the format based on the current year.
 * @param {number} time - Unix timestamp.
 * @param {string} [dateFormat='MMM d, yyyy'] - Desired date format.
 * @returns {string} Formatted date string.
 */
export const messageTimestamp = (time, dateFormat = 'MMM d, yyyy') => {
  const messageTime = fromUnixTime(time);
  const now = new Date();
  const messageDate = format(messageTime, dateFormat);
  if (!isSameYear(messageTime, now)) {
    return format(messageTime, 'LLL d y, h:mm a');
  }
  return messageDate;
};

/**
 * Converts a Unix timestamp to a relative time string (e.g., 3 hours ago).
 * @param {number} time - Unix timestamp.
 * @returns {string} Relative time string.
 */
export const dynamicTime = time => {
  const unixTime = fromUnixTime(time);
  return formatDistanceToNow(unixTime, { addSuffix: true });
};

/**
 * Formats a Unix timestamp into a specified date format.
 * @param {number} time - Unix timestamp.
 * @param {string} [dateFormat='MMM d, yyyy'] - Desired date format.
 * @returns {string} Formatted date string.
 */
export const dateFormat = (time, df = 'MMM d, yyyy') => {
  const unixTime = fromUnixTime(time);
  return format(unixTime, df);
};

/**
 * Converts a detailed time description into a shorter format, optionally appending 'ago'.
 * @param {string} time - Detailed time description (e.g., 'a minute ago').
 * @param {boolean} [withAgo=false] - Whether to append 'ago' to the result.
 * @returns {string} Shortened time description.
 */
export const shortTimestamp = (time, withAgo = false) => {
  // This function takes a time string and converts it to a short time string
  // with the following format: 1m, 1h, 1d, 1mo, 1y
  // The function also takes an optional boolean parameter withAgo
  // which will add the word "ago" to the end of the time string
  const suffix = withAgo ? ' ago' : '';
  const timeMappings = {
    'less than a minute ago': 'now',
    'a minute ago': `1m${suffix}`,
    'an hour ago': `1h${suffix}`,
    'a day ago': `1d${suffix}`,
    'a month ago': `1mo${suffix}`,
    'a year ago': `1y${suffix}`,
  };
  // Check if the time string is one of the specific cases
  if (timeMappings[time]) {
    return timeMappings[time];
  }
  const convertToShortTime = time
    .replace(/about|over|almost|/g, '')
    .replace(' minute ago', `m${suffix}`)
    .replace(' minutes ago', `m${suffix}`)
    .replace(' hour ago', `h${suffix}`)
    .replace(' hours ago', `h${suffix}`)
    .replace(' day ago', `d${suffix}`)
    .replace(' days ago', `d${suffix}`)
    .replace(' month ago', `mo${suffix}`)
    .replace(' months ago', `mo${suffix}`)
    .replace(' year ago', `y${suffix}`)
    .replace(' years ago', `y${suffix}`);
  return convertToShortTime;
};

/**
 * Converts a Unix timestamp into a shorter format, optionally appending 'ago'.
 * Uses date-fns difference functions for accurate calculation.
 * @param {object} params - Parameters object.
 * @param {number} params.time - Unix timestamp.
 * @param {boolean} [params.withAgo=false] - Whether to append 'ago' to the result.
 * @param {Function} [params.t] - Translation function.
 * @returns {string} Shortened time description.
 */
export const shortTimestampFromDate = ({ time, withAgo = false, t }) => {
  const unixTime = fromUnixTime(time);
  const now = new Date();

  const nowLabel = t ? t('TIME.NOW') : 'now';
  const agoLabel = t ? t('TIME.AGO') : 'ago';
  const units = {
    m: t ? t('TIME.UNITS.MINUTE') : 'm',
    h: t ? t('TIME.UNITS.HOUR') : 'h',
    d: t ? t('TIME.UNITS.DAY') : 'd',
    mo: t ? t('TIME.UNITS.MONTH') : 'mo',
    y: t ? t('TIME.UNITS.YEAR') : 'y',
  };

  const suffix = withAgo ? ` ${agoLabel}` : '';

  const seconds = differenceInSeconds(now, unixTime);
  if (seconds < 60) return nowLabel;

  const minutes = differenceInMinutes(now, unixTime);
  if (minutes < 60) return `${minutes}${units.m}${suffix}`;

  const hours = differenceInHours(now, unixTime);
  if (hours < 24) return `${hours}${units.h}${suffix}`;

  const days = differenceInDays(now, unixTime);
  if (days < 30) return `${days}${units.d}${suffix}`;

  const months = differenceInMonths(now, unixTime);
  if (months < 12) return `${months}${units.mo}${suffix}`;

  const years = differenceInYears(now, unixTime);
  return `${years}${units.y}${suffix}`;
};

/**
 * Calculates the difference in days between now and a given timestamp.
 * @param {Date} now - Current date/time.
 * @param {number} timestampInSeconds - Unix timestamp in seconds.
 * @returns {number} Number of days difference.
 */
export const getDayDifferenceFromNow = (now, timestampInSeconds) => {
  const date = new Date(timestampInSeconds * 1000);
  return differenceInDays(now, date);
};

/**
 * Checks if more than 24 hours have passed since a given timestamp.
 * Useful for determining if retry/refresh actions should be disabled.
 * @param {number} timestamp - Unix timestamp.
 * @returns {boolean} True if more than 24 hours have passed.
 */
export const hasOneDayPassed = timestamp => {
  if (!timestamp) return true; // Defensive check
  return getDayDifferenceFromNow(new Date(), timestamp) >= 1;
};
