import { setActivePinia, createPinia } from 'pinia';
import { useCallsStore } from 'dashboard/stores/calls';
import {
  armOutboundRecorder,
  cleanupWhatsappSession,
  takeEarlyOutboundOutcome,
} from 'dashboard/composables/useWhatsappCallSession';

vi.mock('dashboard/composables/useWhatsappCallSession', () => ({
  armOutboundRecorder: vi.fn(),
  cleanupWhatsappSession: vi.fn(),
  takeEarlyOutboundOutcome: vi.fn(),
}));
vi.mock('dashboard/api/channel/voice/twilioVoiceClient', () => ({
  default: { endClientCall: vi.fn() },
}));

const placed = {
  callSid: 'CALLOUT1',
  callId: 42,
  callDirection: 'outbound',
  provider: 'whatsapp',
};

describe('calls store, a call this tab placed', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });

  it('rings as before when nothing arrived for it first', () => {
    const store = useCallsStore();
    store.addCall(placed);

    expect(takeEarlyOutboundOutcome).toHaveBeenCalledWith(42);
    expect(store.calls).toHaveLength(1);
    expect(store.calls[0].isActive).toBe(false);
    expect(armOutboundRecorder).not.toHaveBeenCalled();
  });

  // On a paired phone the pickup can be broadcast before the tab adds the call.
  it('is added as picked up when the pickup arrived first', () => {
    takeEarlyOutboundOutcome.mockReturnValue('accepted');
    const store = useCallsStore();
    store.addCall(placed);

    expect(store.activeCall?.callSid).toBe('CALLOUT1');
    expect(armOutboundRecorder).toHaveBeenCalled();
  });

  it('is not added when it ended first, and its session is released', () => {
    takeEarlyOutboundOutcome.mockReturnValue('ended');
    const store = useCallsStore();
    store.addCall(placed);

    expect(store.calls).toHaveLength(0);
    expect(cleanupWhatsappSession).toHaveBeenCalled();
  });
});
