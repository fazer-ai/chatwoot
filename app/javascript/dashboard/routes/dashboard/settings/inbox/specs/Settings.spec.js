import Settings from '../Settings.vue';

const computeWhatsappUnauthorized = context =>
  Settings.computed.whatsappUnauthorized.call(context);

describe('Inbox Settings', () => {
  it('shows WhatsApp reauthorization for embedded signup inboxes without checking account feature flags', () => {
    const isFeatureEnabledonAccount = vi.fn(() => false);

    const result = computeWhatsappUnauthorized({
      accountId: 1,
      isAWhatsAppCloudChannel: true,
      isEmbeddedSignupWhatsApp: true,
      isFeatureEnabledonAccount,
      isOnChatwootCloud: true,
      inbox: {
        reauthorization_required: true,
      },
    });

    expect(result).toBe(true);
    expect(isFeatureEnabledonAccount).not.toHaveBeenCalled();
  });

  it('does not show WhatsApp reauthorization for manual WhatsApp inboxes', () => {
    const result = computeWhatsappUnauthorized({
      isAWhatsAppCloudChannel: true,
      isEmbeddedSignupWhatsApp: false,
      inbox: {
        reauthorization_required: true,
      },
    });

    expect(result).toBe(false);
  });

  describe('legacy WhatsApp provider', () => {
    const catalog = [
      { key: 'native', creatable: true },
      { key: 'baileys', creatable: true, legacy: true },
      { key: 'zapi', creatable: false, legacy: true },
    ];
    const descriptorFor = key => catalog.find(p => p.key === key);

    it.each([
      ['baileys', true],
      ['zapi', true],
      ['native', false],
      ['whatsapp_cloud', false],
    ])('takes %s as legacy: %s, from the catalog', (provider, legacy) => {
      const result = Settings.computed.isLegacyWhatsAppProvider.call({
        isAWhatsAppChannel: true,
        whatsAppAPIProvider: provider,
        descriptorFor,
      });

      expect(result).toBe(legacy);
    });

    it('recommends the native provider only when the account can pick it', () => {
      const available = creatable =>
        Settings.computed.isNativeWhatsAppAvailable.call({
          creatableProviders: creatable,
        });

      expect(available(catalog.filter(p => p.creatable))).toBe(true);
      expect(available([{ key: 'baileys', creatable: true }])).toBe(false);
    });

    it('opens the conversion with the native provider picked', () => {
      const push = vi.fn();
      Settings.methods.goToConvertToNative.call({
        $router: { push },
        $route: { params: { accountId: 3 } },
        inbox: { id: 7 },
      });

      expect(push).toHaveBeenCalledWith({
        name: 'settings_inbox_convert',
        params: { accountId: 3, inboxId: 7 },
        query: { provider: 'native' },
      });
    });
  });
});
