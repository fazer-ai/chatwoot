import { shallowMount } from '@vue/test-utils';
import WhatsappLinkDeviceModal from '../WhatsappLinkDeviceModal.vue';

const IMPORT_TITLE_KEY =
  'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.IMPORT_SESSION_TITLE';

const mountModal = capabilities =>
  shallowMount(WhatsappLinkDeviceModal, {
    props: {
      show: true,
      onClose: () => {},
      inbox: {
        id: 1,
        name: 'WhatsApp',
        capabilities,
        provider_connection: { connection: 'close' },
      },
    },
    global: {
      mocks: { $t: key => key },
      stubs: {
        'woot-modal': { template: '<div><slot /></div>' },
        'router-link': true,
      },
    },
  });

vi.mock('vuex', () => ({
  useStore: () => ({ dispatch: () => Promise.resolve() }),
}));

describe('WhatsappLinkDeviceModal', () => {
  // The extension hands over Baileys credentials, so a provider that cannot consume
  // them must not be offered an install and a scan that end in a refused request.
  it('hides the session import when the provider cannot accept one', () => {
    const wrapper = mountModal(['qr_pairing']);

    expect(wrapper.html()).not.toContain(IMPORT_TITLE_KEY);
  });

  it('offers the session import when the provider declares it', () => {
    const wrapper = mountModal(['qr_pairing', 'session_import']);

    expect(wrapper.html()).toContain(IMPORT_TITLE_KEY);
  });
});
