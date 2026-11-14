// Dates and times shown to a person read in the app language (the dashboard
// UI language, the widget locale), through shared/helpers/localizedDate.js.
// These rules stop a display format from bypassing it: date-fns formatters
// write English only, and Intl or toLocale* without the app locale follow the
// browser language instead. Machine formats (API parameters, file names) use
// `formatFixed` from the same module, which says so at the call site.
const airbnbRestrictedSyntax = require('eslint-config-airbnb-base/rules/style')
  .rules['no-restricted-syntax'];

const HELPER = 'shared/helpers/localizedDate';
const IMPORT_MESSAGE = `Dates shown to people go through ${HELPER} (formatLocalized, formatRelative, formatElapsed); machine formats use formatFixed.`;
const LOCALE_MESSAGE = `Pass the app locale (currentDateLocale() from ${HELPER}), not the browser's.`;

const DATE_FNS_FORMATTERS = [
  'format',
  'formatDistance',
  'formatDistanceStrict',
  'formatDistanceToNow',
  'formatDistanceToNowStrict',
  'formatRelative',
  'intlFormat',
  'intlFormatDistance',
];

const BROWSER_LOCALE_ARGUMENT = [
  // toLocaleDateString(), toLocaleTimeString(undefined, ...)
  '[arguments.length=0]',
  "[arguments.0.type='Identifier'][arguments.0.name='undefined']",
  "[arguments.0.object.name='navigator'][arguments.0.property.name='language']",
  // vue-i18n's `locale.value` is `pt_BR`, which Intl rejects.
  "[arguments.0.object.name='locale'][arguments.0.property.name='value']",
];

module.exports = {
  rules: {
    'no-restricted-imports': [
      'error',
      {
        paths: [
          {
            name: 'date-fns',
            importNames: DATE_FNS_FORMATTERS,
            message: IMPORT_MESSAGE,
          },
          { name: 'date-fns/locale', message: IMPORT_MESSAGE },
          ...DATE_FNS_FORMATTERS.map(name => ({
            name: `date-fns/${name}`,
            message: IMPORT_MESSAGE,
          })),
        ],
      },
    ],
    'no-restricted-syntax': [
      ...airbnbRestrictedSyntax,
      ...BROWSER_LOCALE_ARGUMENT.flatMap(argument => [
        {
          selector: `CallExpression[callee.property.name=/^toLocale(Date|Time)String$/]${argument}`,
          message: LOCALE_MESSAGE,
        },
        {
          selector: `NewExpression[callee.object.name='Intl'][callee.property.name=/^(DateTimeFormat|RelativeTimeFormat)$/]${argument}`,
          message: LOCALE_MESSAGE,
        },
      ]),
    ],
  },
  overrides: [
    {
      // Stories are design-system demos, not screens people read.
      files: ['**/*.story.vue'],
      rules: { 'no-restricted-syntax': airbnbRestrictedSyntax },
    },
    {
      files: [
        `app/javascript/${HELPER}.js`,
        '**/*.spec.{j,t}s?(x)',
        '**/*.story.vue',
      ],
      rules: { 'no-restricted-imports': 'off' },
    },
  ],
};
