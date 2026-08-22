import { shallowMount, flushPromises } from '@vue/test-utils';
import WhatsappLinkDeviceModal from '../WhatsappLinkDeviceModal.vue';

const KEY = 'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL';
const IMPORT_TITLE_KEY = `${KEY}.IMPORT_SESSION_TITLE`;
const USE_PAIRING_CODE_KEY = `${KEY}.USE_PAIRING_CODE`;
const USE_QRCODE_KEY = `${KEY}.USE_QRCODE`;
const LOADING_PAIRING_CODE_KEY = `${KEY}.LOADING_PAIRING_CODE`;

const dispatch = vi.fn(() => Promise.resolve());

vi.mock('vuex', () => ({
  useStore: () => ({ dispatch: (...args) => dispatch(...args) }),
}));

const mountModal = (
  capabilities,
  providerConnection = { connection: 'close' }
) =>
  shallowMount(WhatsappLinkDeviceModal, {
    props: {
      show: true,
      onClose: () => {},
      inbox: {
        id: 1,
        name: 'WhatsApp',
        capabilities,
        provider_connection: providerConnection,
      },
    },
    global: {
      mocks: { $t: key => key },
      stubs: {
        'woot-modal': { template: '<div><slot /></div>' },
        'router-link': true,
        Button: { props: ['label'], template: '<button>{{ label }}</button>' },
      },
    },
  });

beforeEach(() => dispatch.mockClear());

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

  describe('pairing by code', () => {
    const connecting = {
      connection: 'connecting',
      qr_data_url: 'data:image/png;base64,x',
    };

    it('is not offered by a provider that cannot do it', () => {
      const wrapper = mountModal(['qr_pairing'], connecting);

      expect(wrapper.html()).not.toContain(USE_PAIRING_CODE_KEY);
    });

    it('is offered next to the QR when the provider declares it', () => {
      const wrapper = mountModal(['qr_pairing', 'code_pairing'], connecting);

      expect(wrapper.html()).toContain(USE_PAIRING_CODE_KEY);
    });

    // The code takes a moment to arrive, and the QR is still on the record until it
    // does: leaving it up would put the operator back on the thing they just said they
    // could not use.
    it('waits for the code instead of falling back to the QR', async () => {
      const wrapper = mountModal(['qr_pairing', 'code_pairing'], connecting);

      await wrapper.find('button').trigger('click');
      await flushPromises();

      expect(dispatch).toHaveBeenCalledWith('inboxes/requestPairingCode', 1);
      expect(wrapper.html()).toContain(LOADING_PAIRING_CODE_KEY);
      expect(wrapper.html()).not.toContain('data:image/png;base64,x');
    });

    it('shows the code the provider issued, and the way back to the QR', async () => {
      const wrapper = mountModal(['qr_pairing', 'code_pairing'], {
        ...connecting,
        pairing_code: 'K7QP-2M4X',
      });

      await wrapper.find('button').trigger('click');
      await flushPromises();

      expect(wrapper.html()).toContain('K7QP-2M4X');
      expect(wrapper.html()).toContain(USE_QRCODE_KEY);
    });
  });
});
