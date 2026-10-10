import { describe, it, expect, vi } from 'vitest';
import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import ConversationCallButton from '../ConversationCallButton.vue';

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: () => ref({}),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => true }),
}));
vi.mock('dashboard/composables/useWhatsappCallSession', () => ({
  useWhatsappCallSession: () => ({
    isInitiating: ref(false),
    initiateOutboundCall: vi.fn(),
  }),
}));
vi.mock('dashboard/stores/calls', () => ({
  useCallsStore: () => ({ hasActiveCall: false, hasIncomingCall: false }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', async () => {
  const actual = await vi.importActual('vue-i18n');
  return { ...actual, useI18n: () => ({ t: key => key }) };
});

const INBOX = { id: 3, channel_type: 'Channel::Whatsapp', voice_enabled: true };

const mountButton = chat => {
  const tooltips = [];
  const wrapper = mount(ConversationCallButton, {
    props: { inbox: INBOX, chat },
    global: {
      directives: {
        tooltip: { mounted: (el, binding) => tooltips.push(binding.value) },
      },
      stubs: {
        NextButton: {
          props: ['disabled'],
          template: '<button class="call" :disabled="disabled" />',
        },
      },
    },
  });
  return { wrapper, tooltips };
};

describe('ConversationCallButton', () => {
  // Hidden, the button left the agent guessing why a group had no call.
  it('shows a disabled button that says why in a group conversation', () => {
    const { wrapper, tooltips } = mountButton({ id: 1, group_type: 'group' });

    expect(wrapper.find('button.call').attributes('disabled')).toBeDefined();
    expect(tooltips).toEqual([
      'CONVERSATION.HEADER.WHATSAPP_CALL_GROUP_UNSUPPORTED',
    ]);
  });

  it('offers the call in a conversation with a person', () => {
    const { wrapper, tooltips } = mountButton({ id: 1 });

    expect(wrapper.find('button.call').attributes('disabled')).toBeUndefined();
    expect(tooltips).toEqual(['CONVERSATION.HEADER.WHATSAPP_CALL']);
  });
});
