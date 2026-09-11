import { shallowMount } from '@vue/test-utils';
import ButtonV4 from 'next/button/Button.vue';
import AccountHealth from '../AccountHealth.vue';

const { locale } = vi.hoisted(() => ({ locale: { value: 'en' } }));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
    te: () => false,
    locale,
  }),
}));

describe('AccountHealth', () => {
  const mountComponent = (healthData, props = {}) =>
    shallowMount(AccountHealth, {
      props: { healthData, ...props },
    });

  beforeEach(() => {
    locale.value = 'en';
    vi.spyOn(window, 'open').mockImplementation(() => {});
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('opens the phone numbers page for the correct WhatsApp Business Account', async () => {
    const wrapper = mountComponent({
      business_account_id: 'waba-456',
      business_portfolio_id: 'business-123',
    });

    await wrapper.findComponent(ButtonV4).trigger('click');

    expect(window.open).toHaveBeenCalledWith(
      'https://business.facebook.com/latest/whatsapp_manager/phone_numbers/?business_id=business-123&asset_id=waba-456',
      '_blank'
    );
  });

  it('opens Meta Business Manager when the WhatsApp Business Account ID is unavailable', async () => {
    const wrapper = mountComponent({
      business_portfolio_id: 'business-123',
    });

    await wrapper.findComponent(ButtonV4).trigger('click');

    expect(window.open).toHaveBeenCalledWith(
      'https://business.facebook.com/',
      '_blank'
    );
  });

  it('formats unknown messaging tiers and account modes without exposing translation keys', () => {
    const wrapper = mountComponent({
      messaging_limit_tier: 'TIER_CUSTOM',
      account_mode: 'CUSTOM_MODE',
    });

    expect(wrapper.text()).toContain('Tier Custom');
    expect(wrapper.text()).toContain('Custom Mode');
    expect(wrapper.text()).not.toContain(
      'INBOX_MGMT.ACCOUNT_HEALTH.VALUES.TIERS.TIER_CUSTOM'
    );
    expect(wrapper.text()).not.toContain(
      'INBOX_MGMT.ACCOUNT_HEALTH.VALUES.MODES.CUSTOM_MODE'
    );
  });

  it('formats dates for underscore-based locales', () => {
    locale.value = 'pt_BR';

    const wrapper = mountComponent({
      last_onboarded_time: '2026-05-29T20:11:58+0000',
    });

    expect(wrapper.text()).toContain('2026');
  });

  // Meta answers with the effective webhook configuration, and the chip above reads it as two
  // states: ours, or not ours. Both readings cover a number that owns its routing and a number
  // that owns none, which are different problems with different repairs.
  describe('when the number itself is not pointed at this installation', () => {
    const expectedUrl = 'https://chat.example.com/webhooks/whatsapp/+123';
    const elsewhereUrl = 'https://elsewhere.example.com/webhooks/whatsapp/+123';

    it('says so even though the card is green, because delivery rides on the app URL', () => {
      const wrapper = mountComponent({
        webhook_configuration: { application: expectedUrl },
        expected_webhook_url: expectedUrl,
        routed_by_app_callback_only: true,
      });

      expect(wrapper.text()).toContain(
        'INBOX_MGMT.ACCOUNT_HEALTH.WEBHOOK.RIDES_ON_APP_CALLBACK'
      );
    });

    // Meta routes at three levels, and only the third one belongs to the app. A WABA-level
    // override pointing here is this account's own routing: changing the app callback does not
    // touch it.
    it('stays quiet when the business account is the one pointed here', () => {
      const wrapper = mountComponent({
        webhook_configuration: {
          whatsapp_business_account: expectedUrl,
          application: elsewhereUrl,
        },
        expected_webhook_url: expectedUrl,
        routed_by_app_callback_only: false,
      });

      expect(wrapper.text()).not.toContain('APP_CALLBACK');
    });

    it('stays quiet when the override is in place for this number', () => {
      const wrapper = mountComponent({
        webhook_configuration: {
          phone_number: expectedUrl,
          application: elsewhereUrl,
        },
        expected_webhook_url: expectedUrl,
        routed_by_app_callback_only: false,
      });

      expect(wrapper.text()).not.toContain('APP_CALLBACK');
    });

    // An override of its own pointing at the wrong place is a mismatch the button above repairs:
    // registering rewrites that override. Saying anything about the app callback here would be
    // false, since the app callback is not what delivery follows.
    it('leaves the mismatch chip alone when the number has an override of its own', () => {
      const wrapper = mountComponent({
        webhook_configuration: {
          phone_number: elsewhereUrl,
          application: expectedUrl,
        },
        expected_webhook_url: expectedUrl,
        routed_by_app_callback_only: false,
      });

      expect(wrapper.text()).toContain(
        'INBOX_MGMT.ACCOUNT_HEALTH.WEBHOOK.URL_MISMATCH'
      );
      expect(wrapper.text()).not.toContain('APP_CALLBACK');
    });

    // The same chip, the other repair. With no override of its own, the URL on the card IS the
    // app callback, and the button writes the per-number override that Meta refuses for exactly
    // these accounts: it comes back identical and the operator presses again. The sentence is the
    // only thing on the screen that sends them to the app's own callback.
    it('says the button cannot repoint it when the app callback is what points elsewhere', () => {
      const wrapper = mountComponent({
        webhook_configuration: { application: elsewhereUrl },
        expected_webhook_url: expectedUrl,
        routed_by_app_callback_only: true,
      });

      expect(wrapper.text()).toContain(
        'INBOX_MGMT.ACCOUNT_HEALTH.WEBHOOK.URL_MISMATCH'
      );
      expect(wrapper.text()).toContain(
        'INBOX_MGMT.ACCOUNT_HEALTH.WEBHOOK.APP_CALLBACK_POINTS_ELSEWHERE'
      );
      // The sentence for a URL that still points here would be a lie about one that does not.
      expect(wrapper.text()).not.toContain(
        'INBOX_MGMT.ACCOUNT_HEALTH.WEBHOOK.RIDES_ON_APP_CALLBACK'
      );
    });

    // Nothing configured at all is the chip's own case, and its button is the repair.
    it('stays quiet when there is no webhook configuration to ride on', () => {
      const wrapper = mountComponent({
        webhook_configuration: {},
        expected_webhook_url: expectedUrl,
        routed_by_app_callback_only: true,
      });

      expect(wrapper.text()).toContain(
        'INBOX_MGMT.ACCOUNT_HEALTH.WEBHOOK.ACTION_REQUIRED'
      );
      expect(wrapper.text()).not.toContain('APP_CALLBACK');
    });
  });

  it('shows the current error instead of stale health data', () => {
    const wrapper = mountComponent(
      { verified_name: 'Stale Business Name' },
      {
        healthError: {
          type: 'authorization',
          message: 'The connection needs to be refreshed',
        },
        isEmbeddedSignup: true,
      }
    );

    expect(wrapper.text()).toContain('The connection needs to be refreshed');
    expect(wrapper.text()).not.toContain('Stale Business Name');
  });
});
