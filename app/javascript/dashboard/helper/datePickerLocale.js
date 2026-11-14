// vue-datepicker-next keeps one global default locale, read by every picker
// when it mounts. Registering the app language there translates the month and
// weekday names of all of them (custom snooze, scheduled messages, reports)
// without touching each component. Built from Intl, so it covers every
// language the dashboard ships instead of the few the library bundles.
import { watch } from 'vue';
import DatePicker from 'vue-datepicker-next';
import {
  currentDateLocale,
  formatLocalized,
} from 'shared/helpers/localizedDate';

// 2024-01-07 was a Sunday, the first day the library's arrays expect.
const sundayOffset = day => new Date(2024, 0, 7 + day);
const monthOf = month => new Date(2024, month, 1);
const range = length => Array.from({ length }, (_, index) => index);

export const datePickerLang = locale => {
  const parts = new Intl.DateTimeFormat(locale, {
    month: 'long',
    year: 'numeric',
  })
    .formatToParts(new Date(2024, 0, 1))
    .map(part => part.type);
  const monthFirst = parts.indexOf('month') < parts.indexOf('year');
  return {
    formatLocale: {
      months: range(12).map(m => formatLocalized(monthOf(m), 'LLLL')),
      monthsShort: range(12).map(m => formatLocalized(monthOf(m), 'LLL')),
      weekdays: range(7).map(d => formatLocalized(sundayOffset(d), 'EEEE')),
      weekdaysShort: range(7).map(d => formatLocalized(sundayOffset(d), 'EEE')),
      weekdaysMin: range(7).map(d =>
        formatLocalized(sundayOffset(d), 'EEEEEE')
      ),
      firstDayOfWeek: 0,
      firstWeekContainsDate: 1,
    },
    yearFormat: 'YYYY',
    monthFormat: 'MMM',
    monthBeforeYear: monthFirst,
  };
};

export const bindDatePickerLocale = () =>
  watch(
    currentDateLocale,
    locale => DatePicker.locale(locale, datePickerLang(locale)),
    { immediate: true }
  );
