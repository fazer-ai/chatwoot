const LANG_TO_CURRENCY = {
  pt: 'BRL',
  es: 'EUR',
};

const resolveCurrency = locale => {
  const lang = (locale || 'en').toLowerCase().split(/[-_]/)[0];
  return LANG_TO_CURRENCY[lang] || 'USD';
};

export const formatCurrency = (value, locale) => {
  const num = Number(value);
  if (!Number.isFinite(num)) return '';

  const normalizedLocale = (locale || 'en').replace('_', '-');
  return new Intl.NumberFormat(normalizedLocale, {
    style: 'currency',
    currency: resolveCurrency(locale),
  }).format(num);
};
