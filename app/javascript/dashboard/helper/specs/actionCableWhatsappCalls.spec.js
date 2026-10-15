import { describe, it, beforeEach, expect, vi } from 'vitest';
import { setActivePinia, createPinia } from 'pinia';
import ActionCableConnector from '../actionCable';
import { useCallsStore } from 'dashboard/stores/calls';
import {
  isLocalWhatsappCall,
  noteEarlyOutboundOutcome,
} from 'dashboard/composables/useWhatsappCallSession';

vi.mock('shared/helpers/mitt', () => ({ emitter: { emit: vi.fn() } }));
vi.mock('dashboard/composables/useImpersonation', () => ({
  useImpersonation: () => ({ isImpersonating: { value: false } }),
}));
vi.mock(
  'dashboard/composables/useWhatsappCallSession',
  async importOriginal => ({
    ...(await importOriginal()),
    isLocalWhatsappCall: vi.fn(() => false),
    noteEarlyOutboundOutcome: vi.fn(),
    takeEarlyOutboundOutcome: vi.fn(),
  })
);

global.chatwootConfig = { websocketURL: 'wss://test.chatwoot.com' };

describe('ActionCableConnector, a WhatsApp call that ends before the tab placing it knows it', () => {
  let actionCable;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    actionCable = ActionCableConnector.init(
      {
        dispatch: vi.fn(),
        getters: {
          getCurrentAccountId: 1,
          'accounts/isFeatureEnabledonAccount': vi.fn(() => true),
        },
      },
      'test-token'
    );
  });

  const ended = { provider: 'whatsapp', id: 42, call_id: 'CALLOUT1' };

  it('keeps the end when nothing added the call yet', async () => {
    await actionCable.onVoiceCallEnded(ended);

    expect(noteEarlyOutboundOutcome).toHaveBeenCalledWith(42, 'ended');
  });

  // The message can add the ringing call while the request placing it is still out.
  it('keeps the end when a message already added the call', async () => {
    useCallsStore().calls.push({
      callSid: 'CALLOUT1',
      callId: 42,
      provider: 'whatsapp',
      isActive: false,
    });
    isLocalWhatsappCall.mockReturnValue(false);

    await actionCable.onVoiceCallEnded(ended);

    expect(noteEarlyOutboundOutcome).toHaveBeenCalledWith(42, 'ended');
    expect(useCallsStore().calls).toHaveLength(0);
  });
});
