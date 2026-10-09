import { setActivePinia, createPinia } from 'pinia';
import WhatsappCallsAPI from 'dashboard/api/channel/whatsapp/whatsappCallsAPI';
import { useCallsStore } from 'dashboard/stores/calls';
import { markCallDismissed } from 'dashboard/helper/voice';
import {
  applyOutboundAnswer,
  armOutboundRecorder,
  cleanupWhatsappSession,
  OUTBOUND_RINGING_LIMIT_MS,
  handleWhatsappRemoteEnd,
  hasActiveWhatsappCall,
  noteEarlyOutboundOutcome,
  takeEarlyOutboundEnd,
  useWhatsappCallSession,
} from 'dashboard/composables/useWhatsappCallSession';

vi.mock('dashboard/helper/voice', async importOriginal => ({
  ...(await importOriginal()),
  markCallDismissed: vi.fn(),
}));
vi.mock('dashboard/api/channel/whatsapp/whatsappCallsAPI', () => ({
  default: {
    initiate: vi.fn(),
    terminate: vi.fn(() => Promise.resolve()),
  },
}));

let peers = [];
// Stands in for the browser's peer connection: enough of it to place a call, and a way
// to make its transport fail.
function FakePeerConnection() {
  const peer = {
    connectionState: 'new',
    iceGatheringState: 'complete',
    localDescription: { sdp: 'v=0\r\n' },
    addTrack: () => {},
    createOffer: () => Promise.resolve({ type: 'offer', sdp: 'v=0\r\n' }),
    setLocalDescription: () => Promise.resolve(),
    setRemoteDescription: () => Promise.resolve(),
    addEventListener: () => {},
    removeEventListener: () => {},
    close: () => {
      peer.connectionState = 'closed';
    },
    fail: () => {
      peer.connectionState = 'failed';
      peer.onconnectionstatechange?.();
    },
  };
  peers.push(peer);
  return peer;
}

describe('useWhatsappCallSession, a call whose transport is lost', () => {
  afterEach(() => cleanupWhatsappSession());

  beforeEach(() => {
    // The failure handler removes the call's card from the store, in every example.
    setActivePinia(createPinia());
    peers = [];
    vi.clearAllMocks();
    global.RTCPeerConnection = FakePeerConnection;
    global.MediaStream = function FakeMediaStream() {
      return {
        getTracks: () => [],
        getAudioTracks: () => [],
        addTrack: () => {},
      };
    };
    Object.defineProperty(global.navigator, 'mediaDevices', {
      configurable: true,
      value: { getUserMedia: () => Promise.resolve({ getTracks: () => [] }) },
    });
  });

  // A paired phone's connector can hang up a call it no longer carries without the end
  // reaching the dashboard, and nothing else would release the call.
  it('ends the call it was placing when the transport fails', async () => {
    WhatsappCallsAPI.initiate.mockResolvedValue({
      id: 42,
      call_id: 'CALLOUT1',
    });
    const session = useWhatsappCallSession();
    await session.initiateOutboundCall({ conversationId: 1 });

    peers.at(-1).fail();

    expect(WhatsappCallsAPI.terminate).toHaveBeenCalledWith(42);
    await vi.waitFor(() => expect(hasActiveWhatsappCall()).toBe(false));
  });

  // Nothing will broadcast the end of a call whose end could not be asked for.
  it('releases the session when the end cannot be asked for either', async () => {
    WhatsappCallsAPI.initiate.mockResolvedValue({
      id: 42,
      call_id: 'CALLOUT1',
    });
    WhatsappCallsAPI.terminate.mockRejectedValueOnce(new Error('offline'));
    const session = useWhatsappCallSession();
    await session.initiateOutboundCall({ conversationId: 1 });
    useCallsStore().addCall({
      callSid: 'CALLOUT1',
      callId: 42,
      callDirection: 'outbound',
      provider: 'whatsapp',
    });

    peers.at(-1).fail();

    await vi.waitFor(() => expect(hasActiveWhatsappCall()).toBe(false));
    await vi.waitFor(() => expect(useCallsStore().calls).toHaveLength(0));
    // So a ringing message still queued for it does not bring it back.
    expect(markCallDismissed).toHaveBeenCalledWith('CALLOUT1');
  });

  // The end went through, but its broadcast is not replayed to a tab whose cable was down.
  it('releases the session and the card when the end went through unannounced', async () => {
    WhatsappCallsAPI.initiate.mockResolvedValue({
      id: 42,
      call_id: 'CALLOUT1',
    });
    const session = useWhatsappCallSession();
    await session.initiateOutboundCall({ conversationId: 1 });
    useCallsStore().addCall({
      callSid: 'CALLOUT1',
      callId: 42,
      callDirection: 'outbound',
      provider: 'whatsapp',
    });

    peers.at(-1).fail();

    expect(WhatsappCallsAPI.terminate).toHaveBeenCalledWith(42);
    await vi.waitFor(() => expect(hasActiveWhatsappCall()).toBe(false));
    await vi.waitFor(() => expect(useCallsStore().calls).toHaveLength(0));
  });

  it('does nothing for a transport that is only being set up', async () => {
    WhatsappCallsAPI.initiate.mockResolvedValue({
      id: 42,
      call_id: 'CALLOUT1',
    });
    const session = useWhatsappCallSession();
    await session.initiateOutboundCall({ conversationId: 1 });

    const peer = peers.at(-1);
    peer.connectionState = 'connecting';
    peer.onconnectionstatechange();

    expect(WhatsappCallsAPI.terminate).not.toHaveBeenCalled();
  });

  // The dial is applying an answer that raced ahead of it when the call ends, and the
  // end tears the session down before the dial returns the call it placed.
  it('keeps an end that tore the session down for the call the dial returns', async () => {
    let answered;
    WhatsappCallsAPI.initiate.mockImplementation(async () => {
      await applyOutboundAnswer(42, 'v=0\r\n');
      peers.at(-1).setRemoteDescription = () =>
        new Promise(resolve => {
          answered = resolve;
        });
      return { id: 42, call_id: 'CALLOUT1' };
    });
    const session = useWhatsappCallSession();
    const dialing = session.initiateOutboundCall({ conversationId: 1 });
    await vi.waitFor(() => expect(answered).toBeDefined());

    noteEarlyOutboundOutcome(42, 'ended');
    await handleWhatsappRemoteEnd(42);
    answered();
    await dialing;

    expect(takeEarlyOutboundEnd(42)).toBe('ended');
  });

  // Asked for by the broadcast and by the store adding the call whose end it kept.
  it('ends a call asked to end twice once, the second waiting for the first', async () => {
    WhatsappCallsAPI.initiate.mockResolvedValue({
      id: 42,
      call_id: 'CALLOUT1',
    });
    const session = useWhatsappCallSession();
    await session.initiateOutboundCall({ conversationId: 1 });

    const first = handleWhatsappRemoteEnd(42);
    const second = handleWhatsappRemoteEnd(42);

    expect(second).toBe(first);
    await first;
    expect(hasActiveWhatsappCall()).toBe(false);
  });

  // Before the callee answers there is no transport whose failure would report a lost call.
  describe('a placed call still ringing', () => {
    afterEach(() => vi.useRealTimers());

    it('is let go of once it rang longer than WhatsApp rings', async () => {
      vi.useFakeTimers();
      WhatsappCallsAPI.initiate.mockResolvedValue({
        id: 42,
        call_id: 'CALLOUT1',
      });
      const session = useWhatsappCallSession();
      await session.initiateOutboundCall({ conversationId: 1 });

      await vi.advanceTimersByTimeAsync(OUTBOUND_RINGING_LIMIT_MS - 1);
      expect(WhatsappCallsAPI.terminate).not.toHaveBeenCalled();
      await vi.advanceTimersByTimeAsync(1);

      expect(WhatsappCallsAPI.terminate).toHaveBeenCalledWith(42);
      await vi.waitFor(() => expect(hasActiveWhatsappCall()).toBe(false));
    });

    it('is left to the transport once the callee picked up', async () => {
      vi.useFakeTimers();
      WhatsappCallsAPI.initiate.mockResolvedValue({
        id: 42,
        call_id: 'CALLOUT1',
      });
      const session = useWhatsappCallSession();
      await session.initiateOutboundCall({ conversationId: 1 });

      armOutboundRecorder();
      await vi.advanceTimersByTimeAsync(OUTBOUND_RINGING_LIMIT_MS * 2);

      expect(WhatsappCallsAPI.terminate).not.toHaveBeenCalled();
    });
  });
});
