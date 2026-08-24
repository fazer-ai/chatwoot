import { describe, it, expect, beforeEach, vi } from 'vitest';
import { defineComponent, nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import WhatsappHistorySync from '../WhatsappHistorySync.vue';
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

const INBOX = {
  id: 7,
  provider: 'baileys',
  name: 'Suporte',
  capabilities: ['history_sync'],
  provider_config: { history_sync: false },
};

const mountSection = async (inbox = INBOX) => {
  const wrapper = mount(WhatsappHistorySync, {
    props: { inbox },
    global: {
      stubs: {
        SettingsSection: defineComponent({
          name: 'SettingsSection',
          inheritAttrs: false,
          template: '<div class="SettingsSection-stub"><slot /></div>',
        }),
        Switch: stub('Switch'),
      },
    },
  });

  await nextTick();
  return wrapper;
};

describe('WhatsappHistorySync', () => {
  beforeEach(() => vi.clearAllMocks());

  // Gated on the capability, not on the provider name: it is offered by a session
  // provider and by the legacy one alike, and by neither of the cloud ones.
  it('renders nothing for a provider that cannot fetch history', async () => {
    const wrapper = await mountSection({ ...INBOX, capabilities: [] });

    expect(wrapper.find('.SettingsSection-stub').exists()).toBe(false);
  });

  it('renders for a provider that can', async () => {
    const wrapper = await mountSection();

    expect(wrapper.find('.SettingsSection-stub').exists()).toBe(true);
  });

  describe('the standing setting', () => {
    it('saves the operator turning it on', async () => {
      const wrapper = await mountSection();
      wrapper.vm.enabled = true;

      await wrapper.vm.saveSetting();

      expect(mockDispatch).toHaveBeenCalledWith('inboxes/updateInbox', {
        id: INBOX.id,
        formData: false,
        channel: { provider_config: { history_sync: true } },
      });
    });

    // The switch has already moved by the time the save fails, so leaving it there shows
    // a setting the server never took -- and the next change event needs a different
    // value, so retrying the one that failed would mean toggling away and back.
    it('puts the switch back when the save is refused', async () => {
      const wrapper = await mountSection({
        ...INBOX,
        provider_config: { history_sync: true },
      });
      mockDispatch.mockRejectedValueOnce(new Error('refused'));
      wrapper.vm.enabled = false;

      await wrapper.vm.saveSetting();

      expect(wrapper.vm.enabled).toBe(true);
    });
  });
});
