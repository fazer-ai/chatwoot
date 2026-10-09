import WhatsappCallsAPI from 'dashboard/api/channel/whatsapp/whatsappCallsAPI';
import {
  cleanupWhatsappSession,
  useWhatsappCallSession,
} from 'dashboard/composables/useWhatsappCallSession';

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
    peers = [];
    vi.clearAllMocks();
    global.RTCPeerConnection = FakePeerConnection;
    global.MediaStream = function FakeMediaStream() {
      return { getTracks: () => [], addTrack: () => {} };
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
});
