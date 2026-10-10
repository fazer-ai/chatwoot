import { describe, it, expect, beforeEach, vi } from 'vitest';
import { defineComponent, h } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import WhatsappCallingPage from '../WhatsappCallingPage.vue';
import InboxesAPI from 'dashboard/api/inboxes';

vi.mock('dashboard/api/inboxes', () => ({
  default: {
    enableWhatsappCalling: vi.fn(),
    disableWhatsappCalling: vi.fn(),
    setInboundCalls: vi.fn(),
  },
}));

const mockAlert = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => mockAlert(...args),
}));

const ToggleSection = defineComponent({
  name: 'SettingsToggleSection',
  props: {
    modelValue: { type: Boolean, default: false },
    description: { type: String, default: '' },
    hideToggle: { type: Boolean, default: false },
  },
  emits: ['update:modelValue'],
  setup(props, { slots, emit }) {
    return () =>
      h('div', [
        h('p', { class: 'description' }, props.description),
        props.hideToggle
          ? slots.hiddenToggle?.()
          : h('button', {
              class: 'switch',
              onClick: () => emit('update:modelValue', !props.modelValue),
            }),
      ]);
  },
});

const mountPage = (provider_config, extra = {}) =>
  mount(WhatsappCallingPage, {
    props: { inbox: { id: 7, provider: 'native', provider_config, ...extra } },
    global: {
      mocks: {
        $t: (key, params) =>
          params ? `${key} ${JSON.stringify(params)}` : key,
        $store: { dispatch: vi.fn() },
      },
      stubs: {
        SettingsToggleSection: ToggleSection,
        SettingsFieldSection: true,
        CallRecordingSettings: true,
        NextButton: true,
        TextArea: true,
        Spinner: true,
        'woot-code': true,
      },
    },
  });

describe('WhatsappCallingPage on a paired phone', () => {
  beforeEach(() => vi.clearAllMocks());

  // The connector carries no call through a proxy: the page says so instead of a switch
  // that only fails when pressed.
  it('offers no switch on an inbox that leaves through a proxy, and says what to change', () => {
    const wrapper = mountPage({ proxy_url: 'socks5://proxy.example:1080' });

    expect(wrapper.find('.switch').exists()).toBe(false);
    expect(wrapper.find('[data-test-id="calling-blocked"]').exists()).toBe(
      true
    );
    expect(wrapper.find('.description').text()).toContain(
      'INBOX_MGMT.WHATSAPP_CALLING.ENABLE.PROXY_BLOCKED'
    );
    expect(wrapper.find('.description').text()).toContain(
      'INBOX_MGMT.TABS.CONFIGURATION'
    );
  });

  it('offers the switch on an inbox without a proxy', () => {
    const wrapper = mountPage({});

    expect(wrapper.find('.switch').exists()).toBe(true);
    expect(wrapper.find('.description').text()).toBe(
      'INBOX_MGMT.WHATSAPP_CALLING.ENABLE.PAIRED_DESCRIPTION'
    );
  });

  // Without the UDP port the connector carries no call voice, and enabling would offer
  // agents calls that all fail.
  it('offers no switch when the connector does not carry calls, and says what is missing', () => {
    const wrapper = mountPage({}, { voice_calls_carried: false });

    expect(wrapper.find('.switch').exists()).toBe(false);
    expect(wrapper.find('.description').text()).toBe(
      'INBOX_MGMT.WHATSAPP_CALLING.ENABLE.CONNECTOR_WITHOUT_CALLS'
    );
  });

  it('keeps the switch to turn calls off when they were on and the connector stopped carrying them', () => {
    const wrapper = mountPage(
      { calling_enabled: true },
      { voice_calls_carried: false }
    );

    expect(wrapper.find('.switch').exists()).toBe(true);
    expect(wrapper.find('.description').text()).toBe(
      'INBOX_MGMT.WHATSAPP_CALLING.ENABLE.CONNECTOR_WITHOUT_CALLS'
    );
  });

  it('shows the reason the server gives for refusing to turn calls on', async () => {
    InboxesAPI.enableWhatsappCalling.mockRejectedValue({
      response: { data: { error: 'As ligações não passam por proxy.' } },
    });
    const wrapper = mountPage({});

    await wrapper.find('.switch').trigger('click');
    await flushPromises();

    expect(mockAlert).toHaveBeenCalledWith('As ligações não passam por proxy.');
  });
});
