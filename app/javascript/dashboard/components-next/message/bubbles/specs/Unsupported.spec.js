import { defineComponent, ref, computed } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import Unsupported from '../Unsupported.vue';
import { provideMessageContext } from '../../provider.js';

vi.mock('dashboard/composables/useInbox', () => ({
  useInbox: () => ({
    isAFacebookInbox: computed(() => false),
    isAnInstagramChannel: computed(() => false),
    isATiktokChannel: computed(() => false),
    isAWhatsAppChannel: computed(() => true),
  }),
}));

const mountUnsupported = contentAttributes => {
  const TestHost = defineComponent({
    components: { Unsupported },
    setup() {
      provideMessageContext({
        inboxId: ref(1),
        contentAttributes: ref(contentAttributes),
      });
    },
    template: '<Unsupported />',
  });

  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: {
      en: {
        CONVERSATION: {
          UNSUPPORTED_MESSAGE_WHATSAPP: 'This message is not supported.',
          MASKED_MESSAGE_WHATSAPP:
            'WhatsApp does not deliver verification codes to linked devices.',
        },
      },
    },
  });

  return mount(TestHost, {
    global: {
      plugins: [i18n],
      stubs: { BaseBubble: { template: '<div><slot /></div>' } },
    },
  });
};

describe('Unsupported', () => {
  it('explains the masking when WhatsApp withheld the content', () => {
    const wrapper = mountUnsupported({ isUnsupported: true, isMasked: true });

    expect(wrapper.text()).toBe(
      'WhatsApp does not deliver verification codes to linked devices.'
    );
  });

  it('falls back to the channel copy when the type is simply unknown', () => {
    const wrapper = mountUnsupported({ isUnsupported: true });

    expect(wrapper.text()).toBe('This message is not supported.');
  });
});
