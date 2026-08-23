import { describe, it, expect, beforeEach, vi } from 'vitest';
import { defineComponent, nextTick } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import SessionProviderConfiguration from '../SessionProviderConfiguration.vue';
import WhatsappChannel from 'dashboard/api/channel/whatsappChannel';
import InboxesAPI from 'dashboard/api/inboxes';

vi.mock('dashboard/api/channel/whatsappChannel', () => ({
  default: { getSessionProviders: vi.fn() },
}));

vi.mock('dashboard/api/inboxes', () => ({
  default: { syncProviderHistory: vi.fn() },
}));

const mockDispatch = vi.fn();
vi.mock('vuex', () => ({ useStore: () => ({ dispatch: mockDispatch }) }));

vi.mock('vue-i18n', async () => {
  const actual = await vi.importActual('vue-i18n');
  return { ...actual, useI18n: () => ({ t: key => key }) };
});

const mockAlert = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => mockAlert(...args),
}));

const stub = name =>
  defineComponent({ name, template: `<div class="${name}-stub" />` });

const FIELDS = [
  {
    name: 'base_url',
    type: 'url',
    required: true,
    default: null,
    secret: false,
  },
  {
    name: 'token',
    type: 'password',
    required: true,
    default: null,
    secret: true,
  },
  {
    name: 'mark_as_read',
    type: 'boolean',
    required: false,
    default: true,
    secret: false,
  },
];

const catalog = ({ beta }) => [
  { key: 'uazapi', creatable: true, beta, legacy: false, fields: FIELDS },
];

const INBOX = {
  id: 7,
  provider: 'uazapi',
  name: 'Suporte',
  // The server never serves the token back, which is what the save path has to survive.
  provider_config: { base_url: 'https://uaz.example', mark_as_read: true },
};

// Scoped to the connection section, where the connect button is first and the history
// one sits under it. The credential sections further down carry buttons of their own.
const historyButton = wrapper =>
  wrapper.findAll('.SettingsSection-stub')[0].findAll('.NextButton-stub')[1];

const mountPage = async ({ beta = true, inbox = INBOX } = {}) => {
  WhatsappChannel.getSessionProviders.mockResolvedValue({
    data: { payload: catalog({ beta }) },
  });

  const wrapper = mount(SessionProviderConfiguration, {
    props: { inbox },
    global: {
      stubs: {
        WhatsappLinkDeviceModal: stub('WhatsappLinkDeviceModal'),
        InboxName: stub('InboxName'),
        // Rendered rather than stubbed away: the badge lives in its slot.
        SettingsSection: defineComponent({
          name: 'SettingsSection',
          inheritAttrs: false,
          template: '<div class="SettingsSection-stub"><slot /></div>',
        }),
        NextButton: stub('NextButton'),
        Switch: stub('Switch'),
        'woot-input': stub('woot-input'),
      },
    },
  });

  await flushPromises();
  await nextTick();
  return wrapper;
};

describe('SessionProviderConfiguration', () => {
  beforeEach(() => vi.clearAllMocks());

  // Whoever inherits an inbox never saw the picker, so the beta warning has to survive
  // on the page they manage it from.
  it('badges an inbox whose provider the catalog reports as beta', async () => {
    const wrapper = await mountPage({ beta: true });

    expect(wrapper.findComponent({ name: 'Label' }).exists()).toBe(true);
  });

  it('drops the badge once the provider leaves beta', async () => {
    const wrapper = await mountPage({ beta: false });

    expect(wrapper.findComponent({ name: 'Label' }).exists()).toBe(false);
  });

  // A secret is never served back, so its input starts empty. Saving that empty input
  // would replace the stored credential with '' and silently disconnect the inbox.
  it('leaves an untouched secret alone instead of clearing it', async () => {
    const wrapper = await mountPage();
    const token = FIELDS.find(field => field.secret);

    await wrapper.vm.save(token);

    expect(mockDispatch).not.toHaveBeenCalled();
  });

  // The switch has already moved by the time the save fails, so leaving it there shows a
  // setting the server never took -- and the next change event needs a different value,
  // so retrying the one that failed would mean toggling away and back.
  it('puts a preference switch back when the save is refused', async () => {
    const wrapper = await mountPage();
    const preference = FIELDS.find(field => field.type === 'boolean');
    mockDispatch.mockRejectedValueOnce(new Error('refused'));
    wrapper.vm.values[preference.name] = false;

    await wrapper.vm.save(preference);

    expect(wrapper.vm.values[preference.name]).toBe(true);
  });

  it('keeps what was typed into a text field when the save is refused', async () => {
    const wrapper = await mountPage();
    const url = FIELDS.find(field => field.type === 'url');
    mockDispatch.mockRejectedValueOnce(new Error('refused'));
    wrapper.vm.values[url.name] = 'https://moved.example';

    await wrapper.vm.save(url);

    expect(wrapper.vm.values[url.name]).toBe('https://moved.example');
  });

  describe('the history sync button', () => {
    const withHistory = (config = {}, connection = 'open') => ({
      ...INBOX,
      capabilities: ['history_sync'],
      provider_config: { ...INBOX.provider_config, ...config },
      provider_connection: { connection },
    });

    it('is absent on a provider that cannot fetch history', async () => {
      const wrapper = await mountPage();

      expect(historyButton(wrapper)).toBeUndefined();
    });

    // Recovering one weekend must not require turning on the dump that repeats at every
    // future pairing: the two are different decisions and the button owns neither.
    it('does not wait for the connect-time setting', async () => {
      InboxesAPI.syncProviderHistory.mockResolvedValue({});
      const wrapper = await mountPage({
        inbox: withHistory({ history_sync: false }),
      });

      expect(historyButton(wrapper).attributes('disabled')).toBe('false');

      await historyButton(wrapper).trigger('click');
      await flushPromises();

      expect(InboxesAPI.syncProviderHistory).toHaveBeenCalledWith(INBOX.id);
    });

    it('reports back once the phone has been asked', async () => {
      InboxesAPI.syncProviderHistory.mockResolvedValue({});
      const wrapper = await mountPage({
        inbox: withHistory({ history_sync: true }),
      });

      await historyButton(wrapper).trigger('click');
      await flushPromises();

      expect(InboxesAPI.syncProviderHistory).toHaveBeenCalledWith(INBOX.id);
      expect(mockAlert).toHaveBeenCalledWith(
        'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_HISTORY_SYNC.REQUESTED'
      );
    });

    // The request travels to the phone through the session, so with the session down the
    // button would report that it asked and nothing would ever arrive.
    it('is not offered while the session is down', async () => {
      const wrapper = await mountPage({
        inbox: withHistory({ history_sync: true }, 'close'),
      });

      expect(historyButton(wrapper).attributes('disabled')).toBe('true');
    });

    it('reports a request the provider refused', async () => {
      InboxesAPI.syncProviderHistory.mockRejectedValue(new Error('nope'));
      const wrapper = await mountPage({
        inbox: withHistory({ history_sync: true }),
      });

      await historyButton(wrapper).trigger('click');
      await flushPromises();

      expect(mockAlert).toHaveBeenCalledWith(
        'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_HISTORY_SYNC.ERROR'
      );
    });
  });

  it('sends a secret the operator actually typed', async () => {
    const wrapper = await mountPage();
    const token = FIELDS.find(field => field.secret);
    wrapper.vm.values[token.name] = 'new-token';

    await wrapper.vm.save(token);

    expect(mockDispatch).toHaveBeenCalledWith('inboxes/updateInbox', {
      id: INBOX.id,
      formData: false,
      channel: {
        provider_config: { ...INBOX.provider_config, token: 'new-token' },
      },
    });
  });
});
