import { mount, flushPromises } from '@vue/test-utils';
import InboxesAPI from 'dashboard/api/inboxes';
import WhatsappNumberWarning from '../WhatsappNumberWarning.vue';

vi.mock('dashboard/api/inboxes', () => ({
  default: { onWhatsapp: vi.fn() },
}));

const openBaileysInbox = {
  id: 2,
  channelType: 'Channel::Whatsapp',
  provider: 'baileys',
  capabilities: ['check_number'],
  providerConnection: { connection: 'open' },
};
const contact = { id: 7, phoneNumber: '+558588246590' };

const mountWarning = (props = {}) =>
  mount(WhatsappNumberWarning, {
    props: {
      targetInbox: openBaileysInbox,
      selectedContact: contact,
      ...props,
    },
  });

const answer = exists =>
  InboxesAPI.onWhatsapp.mockResolvedValue({ data: { exists } });

describe('WhatsappNumberWarning', () => {
  it('warns when WhatsApp says the number has no account', async () => {
    answer(false);

    const wrapper = mountWarning();
    await flushPromises();

    expect(InboxesAPI.onWhatsapp).toHaveBeenCalledWith(2, '+558588246590');
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  });

  it('stays quiet when WhatsApp knows the number', async () => {
    answer(true);

    const wrapper = mountWarning();
    await flushPromises();

    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });

  // A failed lookup is "unknown", and unknown must not read as "no".
  it('stays quiet when the lookup fails', async () => {
    InboxesAPI.onWhatsapp.mockRejectedValue(new Error('timeout'));

    const wrapper = mountWarning();
    await flushPromises();

    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });

  it('does not ask a session that is not open', async () => {
    answer(false);

    const wrapper = mountWarning({
      targetInbox: {
        ...openBaileysInbox,
        providerConnection: { connection: 'close' },
      },
    });
    await flushPromises();

    expect(InboxesAPI.onWhatsapp).not.toHaveBeenCalled();
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });

  it('reads the phone of a contact opened from its own page', async () => {
    answer(false);

    mountWarning({ selectedContact: { id: 7, phone_number: '+558588246590' } });
    await flushPromises();

    expect(InboxesAPI.onWhatsapp).toHaveBeenCalledWith(2, '+558588246590');
  });

  it('does not ask about a contact without a phone', async () => {
    mountWarning({ selectedContact: { id: 7, email: 'a@b.c' } });
    await flushPromises();

    expect(InboxesAPI.onWhatsapp).not.toHaveBeenCalled();
  });

  // The agent switched contacts while the first lookup was still out: its late "no" belongs
  // to a number that is no longer on screen.
  it('ignores the answer about a contact that is no longer selected', async () => {
    let answerFirst;
    InboxesAPI.onWhatsapp
      .mockReturnValueOnce(
        new Promise(resolve => {
          answerFirst = resolve;
        })
      )
      .mockResolvedValueOnce({ data: { exists: true } });

    const wrapper = mountWarning();
    await wrapper.setProps({
      selectedContact: { id: 8, phoneNumber: '+5585999999999' },
    });
    await flushPromises();
    answerFirst({ data: { exists: false } });
    await flushPromises();

    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });
});
