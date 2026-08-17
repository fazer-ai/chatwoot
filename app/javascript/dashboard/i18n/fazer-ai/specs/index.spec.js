import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n';
import { forkMessages, withForkMessages } from 'dashboard/i18n/fazer-ai';
import upstreamEn from 'dashboard/i18n/locale/en';
import upstreamPtBr from 'dashboard/i18n/locale/pt_BR';
import upstreamEs from 'dashboard/i18n/locale/es';
import upstreamFr from 'dashboard/i18n/locale/fr';

describe('fazer.ai translation overlay', () => {
  it('exposes a fork tree for every language we translate', () => {
    expect(Object.keys(forkMessages).sort()).toEqual(['en', 'es', 'pt_BR']);
  });

  it('adds namespaces that upstream does not ship', () => {
    expect(upstreamEn.INTERNAL_CHAT).toBeUndefined();
    expect(messages.en.INTERNAL_CHAT).toBeDefined();
    expect(messages.pt_BR.SCHEDULED_MESSAGES).toBeDefined();
    expect(messages.es.SCHEDULED_MESSAGES).toBeDefined();
  });

  it('translates the fork keys rather than copying the en tree', () => {
    expect(messages.es.INTERNAL_CHAT.TITLE).toBe('Chat interno');
    expect(messages.es.GROUP.SETTINGS.LEAVE_GROUP).toBe('Salir del grupo');
    expect(messages.es.INBOX_MGMT.CONVERT.BUTTON).not.toBe(
      messages.en.INBOX_MGMT.CONVERT.BUTTON
    );
  });

  it('adds fork keys inside an upstream namespace without dropping upstream keys', () => {
    const upstreamKeys = Object.keys(upstreamEn.INBOX_MGMT);
    const mergedKeys = Object.keys(messages.en.INBOX_MGMT);

    expect(upstreamKeys.every(key => mergedKeys.includes(key))).toBe(true);
    expect(mergedKeys.length).toBeGreaterThan(upstreamKeys.length);
  });

  it('lets overrides.json replace an upstream string', () => {
    expect(messages.en.CONVERSATION.UNSUPPORTED_MESSAGE).not.toBe(
      upstreamEn.CONVERSATION.UNSUPPORTED_MESSAGE
    );
    expect(messages.pt_BR.CONVERSATION.UNSUPPORTED_MESSAGE).not.toBe(
      upstreamPtBr.CONVERSATION.UNSUPPORTED_MESSAGE
    );
    expect(messages.es.CONVERSATION.UNSUPPORTED_MESSAGE).not.toBe(
      upstreamEs.CONVERSATION.UNSUPPORTED_MESSAGE
    );
  });

  it('leaves languages without a fork folder untouched', () => {
    expect(messages.fr).toEqual(upstreamFr);
  });

  it('does not mutate the upstream locale objects', () => {
    expect(upstreamEn.INTERNAL_CHAT).toBeUndefined();
    expect(upstreamPtBr.INTERNAL_CHAT).toBeUndefined();
  });

  it('merges nested objects instead of replacing them', () => {
    const merged = withForkMessages({
      en: { NAMESPACE: { UPSTREAM: 'kept', SHARED: 'upstream' } },
    });

    expect(merged.en.NAMESPACE.UPSTREAM).toBe('kept');
  });

  it('falls back to en for a fork key the language has not translated yet', () => {
    const i18n = createI18n({ legacy: false, locale: 'en', messages });
    i18n.global.locale.value = 'fr';

    expect(i18n.global.t('INTERNAL_CHAT.CHANNELS')).toBe(
      messages.en.INTERNAL_CHAT.CHANNELS
    );
  });
});
