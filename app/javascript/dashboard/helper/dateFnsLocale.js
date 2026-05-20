import { enUS, ptBR } from 'date-fns/locale';

// Maps vue-i18n locale codes (e.g. 'pt_BR', 'en') to the matching date-fns
// `Locale` object. We extend this lazily as we localize new reports; missing
// entries fall back to `enUS` so existing English-by-default screens are
// unaffected. Chatwoot's account locale is the source of truth — read it
// via `useI18n().locale` (Composition API) or `this.$i18n.locale` (Options).
const LOCALES = {
  pt_BR: ptBR,
};

export const resolveDateFnsLocale = vueI18nLocale =>
  LOCALES[vueI18nLocale] || enUS;
