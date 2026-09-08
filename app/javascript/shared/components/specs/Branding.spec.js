import { shallowMount } from '@vue/test-utils';

const mockGlobalConfig = { value: { installationName: 'Chatwoot fazer.ai' } };

vi.mock('dashboard/composables/store.js', () => ({
  useMapGetter: () => mockGlobalConfig,
}));

// Read at module scope by the component, so it has to exist before the import below.
window.globalConfig = {
  BRAND_NAME: 'Chatwoot fazer.ai',
  LOGO_THUMBNAIL: '/brand-assets/logo_thumbnail.svg',
  WIDGET_BRAND_URL: 'https://www.chatwoot.com',
};

const Branding = (await import('../Branding.vue')).default;

const mountBranding = (props = {}) =>
  shallowMount(Branding, {
    props,
    global: {
      mocks: {
        $t: key => (key === 'POWERED_BY' ? 'Powered by Chatwoot' : key),
        $store: { getters: { 'appConfig/getReferrerHost': '' } },
      },
    },
  });

describe('Branding', () => {
  it('names the installation when no brand name is given', () => {
    const wrapper = mountBranding();

    expect(wrapper.text()).toContain('Powered by Chatwoot fazer.ai');
  });

  it('names the account when a brand name is given', () => {
    const wrapper = mountBranding({ brandName: 'Guichê Live' });

    expect(wrapper.text()).toContain('Powered by Guichê Live');
    expect(wrapper.find('img').attributes('alt')).toBe('Guichê Live');
  });

  it('renders nothing when branding is disabled', () => {
    const wrapper = mountBranding({
      brandName: 'Guichê Live',
      disableBranding: true,
    });

    expect(wrapper.find('a').exists()).toBe(false);
  });
});
