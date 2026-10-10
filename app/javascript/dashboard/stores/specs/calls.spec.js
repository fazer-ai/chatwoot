import { setActivePinia, createPinia } from 'pinia';
import { useCallsStore } from 'dashboard/stores/calls';
import {
  armOutboundRecorder,
  cleanupWhatsappSession,
  handleWhatsappRemoteEnd,
  isLocalWhatsappCall,
  takeEarlyOutboundEnd,
  takeEarlyOutboundOutcome,
} from 'dashboard/composables/useWhatsappCallSession';

vi.mock('dashboard/composables/useWhatsappCallSession', () => ({
  armOutboundRecorder: vi.fn(),
  cleanupWhatsappSession: vi.fn(),
  handleWhatsappRemoteEnd: vi.fn(),
  isLocalWhatsappCall: vi.fn(() => true),
  takeEarlyOutboundEnd: vi.fn(),
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

  // Two tabs placing calls at once each buffer both calls' outcomes.
  it('leaves an outcome alone for a call another tab placed', () => {
    isLocalWhatsappCall.mockReturnValueOnce(false);
    takeEarlyOutboundOutcome.mockReturnValue('accepted');
    const store = useCallsStore();
    store.addCall(placed);

    expect(takeEarlyOutboundOutcome).not.toHaveBeenCalled();
    expect(store.calls[0].isActive).toBe(false);
  });

  // The message can add the call this tab placed before the tab itself does.
  it('applies the pickup when the tab adds a call the message added first', () => {
    const store = useCallsStore();
    store.addCall(placed);
    takeEarlyOutboundOutcome.mockReturnValue('accepted');
    store.addCall(placed);

    expect(store.calls).toHaveLength(1);
    expect(store.activeCall?.callSid).toBe('CALLOUT1');
    expect(armOutboundRecorder).toHaveBeenCalled();
  });

  it('is not added when it ended first, and its session is released', () => {
    takeEarlyOutboundOutcome.mockReturnValue('ended');
    const store = useCallsStore();
    store.addCall(placed);

    expect(store.calls).toHaveLength(0);
    // Through the call's end, which uploads the recording before releasing the session.
    expect(handleWhatsappRemoteEnd).toHaveBeenCalledWith(42);
    expect(cleanupWhatsappSession).not.toHaveBeenCalled();
  });

  // The end tore down the session placing it before the dial added the call.
  it('is not added when it ended first and the session placing it is gone already', () => {
    isLocalWhatsappCall.mockReturnValueOnce(false);
    takeEarlyOutboundEnd.mockReturnValue('ended');
    const store = useCallsStore();
    store.addCall(placed);

    expect(store.calls).toHaveLength(0);
    expect(handleWhatsappRemoteEnd).not.toHaveBeenCalled();
    expect(takeEarlyOutboundOutcome).not.toHaveBeenCalled();
  });
});
