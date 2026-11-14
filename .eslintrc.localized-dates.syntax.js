// `no-restricted-syntax` selectors for dates shown to a person: toLocale* and
// Intl formatters must get the app locale, not the browser's (no locale,
// `undefined`, `navigator.language`) and not vue-i18n's raw `locale.value`
// (`pt_BR`, which Intl rejects). Spread into the rule in .eslintrc.js; see
// .eslintrc.localized-dates.js for the rest of the date rules.
const LOCALE_MESSAGE =
  "Pass the app locale (currentDateLocale() from shared/helpers/localizedDate), not the browser's.";

const BROWSER_LOCALE_ARGUMENT = [
  '[arguments.length=0]',
  "[arguments.0.type='Identifier'][arguments.0.name='undefined']",
  "[arguments.0.object.name='navigator'][arguments.0.property.name='language']",
  "[arguments.0.object.name='locale'][arguments.0.property.name='value']",
];

module.exports = BROWSER_LOCALE_ARGUMENT.flatMap(argument => [
  {
    selector: `CallExpression[callee.property.name=/^toLocale(Date|Time)String$/]${argument}`,
    message: LOCALE_MESSAGE,
  },
  {
    selector: `NewExpression[callee.object.name='Intl'][callee.property.name=/^(DateTimeFormat|RelativeTimeFormat)$/]${argument}`,
    message: LOCALE_MESSAGE,
  },
]);
