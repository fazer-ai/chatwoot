import {
  CAPABILITIES,
  SESSION_PROVIDERS,
  hasCapability,
  inboxCapabilities,
  isSessionProvider,
} from '../whatsappSession';

describe('whatsappSession', () => {
  describe('isSessionProvider', () => {
    it.each(SESSION_PROVIDERS)('is true for %s', provider => {
      expect(isSessionProvider(provider)).toBe(true);
    });

    it.each(['whatsapp_cloud', 'default', 'twilio', '', undefined])(
      'is false for %s',
      provider => {
        expect(isSessionProvider(provider)).toBe(false);
      }
    );
  });

  describe('inboxCapabilities', () => {
    it('returns the list the server put on the inbox', () => {
      expect(inboxCapabilities({ capabilities: ['edit', 'groups'] })).toEqual([
        'edit',
        'groups',
      ]);
    });

    it('returns an empty list for an inbox that carries none', () => {
      expect(inboxCapabilities({})).toEqual([]);
      expect(inboxCapabilities(null)).toEqual([]);
      expect(inboxCapabilities(undefined)).toEqual([]);
    });
  });

  describe('hasCapability', () => {
    const inbox = { capabilities: ['edit', 'reactions'] };

    it('is true for a declared capability', () => {
      expect(hasCapability(inbox, CAPABILITIES.EDIT)).toBe(true);
    });

    it('is false for one the provider did not declare', () => {
      expect(hasCapability(inbox, CAPABILITIES.GROUPS)).toBe(false);
    });

    // A gate on an inbox whose payload carries no capabilities must read false rather
    // than throw: the same components render for every channel type.
    it('is false when the inbox carries no capabilities at all', () => {
      expect(hasCapability({}, CAPABILITIES.EDIT)).toBe(false);
      expect(hasCapability(null, CAPABILITIES.EDIT)).toBe(false);
    });
  });
});
