import { mount, flushPromises } from '@vue/test-utils';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import WhatsappNumberMissingBanner from '../WhatsappNumberMissingBanner.vue';

vi.mock('dashboard/api/inbox/conversation', () => ({
  default: { recheckWhatsappNumber: vi.fn() },
}));

const NOW = new Date('2026-10-16T18:00:00Z');
const hoursAgo = hours => Math.floor(NOW.getTime() / 1000) - hours * 3600;

const mountBanner = conversation =>
  mount(WhatsappNumberMissingBanner, {
    props: { conversation: { id: 144873, messages: [], ...conversation } },
    global: { stubs: { Banner: { template: '<div class="banner" />' } } },
  });

describe('WhatsappNumberMissingBanner', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(NOW);
    ConversationAPI.recheckWhatsappNumber.mockResolvedValue({});
  });

  afterEach(() => vi.useRealTimers());

  it('asks again on open once the answer is older than the window', async () => {
    const wrapper = mountBanner({ whatsapp_missing_checked_at: hoursAgo(48) });
    await flushPromises();

    expect(wrapper.find('.banner').exists()).toBe(true);
    expect(ConversationAPI.recheckWhatsappNumber).toHaveBeenCalledWith(144873);
  });

  it('does not ask again inside the window', async () => {
    const wrapper = mountBanner({ whatsapp_missing_checked_at: hoursAgo(1) });
    await flushPromises();

    expect(wrapper.find('.banner').exists()).toBe(true);
    expect(ConversationAPI.recheckWhatsappNumber).not.toHaveBeenCalled();
  });

  // A failed recheck is "unknown": the banner keeps the last real answer.
  it('keeps the banner when the recheck fails', async () => {
    ConversationAPI.recheckWhatsappNumber.mockRejectedValue(new Error('500'));

    const wrapper = mountBanner({ whatsapp_missing_checked_at: hoursAgo(48) });
    await flushPromises();

    expect(wrapper.find('.banner').exists()).toBe(true);
  });

  it('shows nothing and asks nothing for a number not flagged', async () => {
    const wrapper = mountBanner({ whatsapp_missing_checked_at: null });
    await flushPromises();

    expect(wrapper.find('.banner').exists()).toBe(false);
    expect(ConversationAPI.recheckWhatsappNumber).not.toHaveBeenCalled();
  });

  it('hides as soon as the contact writes, before any reload', async () => {
    const wrapper = mountBanner({ whatsapp_missing_checked_at: hoursAgo(1) });
    await wrapper.setProps({
      conversation: {
        id: 144873,
        whatsapp_missing_checked_at: hoursAgo(1),
        messages: [
          { message_type: 0, status: 'sent', created_at: hoursAgo(0) },
        ],
      },
    });

    expect(wrapper.find('.banner').exists()).toBe(false);
  });
});
