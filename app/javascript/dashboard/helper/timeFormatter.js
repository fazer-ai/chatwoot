// Localized replacement for `@chatwoot/utils`' `formatTime`, which hard-codes
// English unit abbreviations ("Min", "Sec", "Hr", "Day") into the returned
// string. Same step thresholds and rounding logic as the upstream helper, but
// the unit labels come from i18n keys under `REPORT.TIME_UNITS.*`. Pass `t`
// (vue-i18n's translation function) so the formatter stays a pure function
// usable from Options API (`this.$t`), Composition API (`useI18n().t`) and
// non-component contexts (chart config callbacks built with `t` in scope).

const KEYS = {
  sec: 'REPORT.TIME_UNITS.SEC',
  min: 'REPORT.TIME_UNITS.MIN',
  hr: 'REPORT.TIME_UNITS.HR',
  day: 'REPORT.TIME_UNITS.DAY',
};

export const formatTimeLocalized = (timeInSeconds, t) => {
  if (timeInSeconds >= 60 && timeInSeconds < 3600) {
    const minutes = Math.floor(timeInSeconds / 60);
    const seconds = minutes === 60 ? 0 : Math.floor(timeInSeconds % 60);
    const head = `${minutes} ${t(KEYS.min)}`;
    return seconds > 0 ? `${head} ${seconds} ${t(KEYS.sec)}` : head;
  }
  if (timeInSeconds >= 3600 && timeInSeconds < 86400) {
    const hours = Math.floor(timeInSeconds / 3600);
    const minutes =
      timeInSeconds % 3600 < 60 || hours === 24
        ? 0
        : Math.floor((timeInSeconds % 3600) / 60);
    const head = `${hours} ${t(KEYS.hr)}`;
    return minutes > 0 ? `${head} ${minutes} ${t(KEYS.min)}` : head;
  }
  if (timeInSeconds >= 86400) {
    const days = Math.floor(timeInSeconds / 86400);
    const hours =
      timeInSeconds % 86400 < 3600 || days >= 364
        ? 0
        : Math.floor((timeInSeconds % 86400) / 3600);
    const head = `${days} ${t(KEYS.day)}`;
    return hours > 0 ? `${head} ${hours} ${t(KEYS.hr)}` : head;
  }
  return `${Math.floor(timeInSeconds)} ${t(KEYS.sec)}`;
};
