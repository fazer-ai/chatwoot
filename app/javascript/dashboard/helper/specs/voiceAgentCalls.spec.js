import { setActivePinia, createPinia } from 'pinia';
import { useCallsStore } from 'dashboard/stores/calls';
import {
  handleVoiceCallCreated,
  handleVoiceCallUpdated,
} from 'dashboard/helper/voice';

// A call a voice agent is answering is recorded ringing before the voice agent
// takes it, and its message must not put a card on the agents' screens; handed
// back to them when the voice agent cannot take it, it rings as any call.
describe('voice calls a voice agent answers', () => {
  const callMessage = ({ callSid, status = 'ringing', voiceAgent }) => ({
    content_type: 'voice_call',
    message_type: 0,
    conversation_id: 7,
    inbox_id: 3,
    conversation: { inbox_id: 3 },
    sender: { id: 99, name: 'Ana Souza' },
    call: {
      id: 1,
      provider_call_id: callSid,
      provider: 'whatsapp',
      direction: 'incoming',
      status,
      voice_agent: voiceAgent,
    },
  });

  beforeEach(() => {
    setActivePinia(createPinia());
  });

  const ringing = () => useCallsStore().calls.map(call => call.callSid);

  it('rings nobody for a call recorded as the voice agent answer', () => {
    handleVoiceCallCreated(
      callMessage({ callSid: 'CALLAI1', voiceAgent: true }),
      1,
      'online'
    );

    expect(ringing()).toEqual([]);
  });

  it('rings for a call without a voice agent', () => {
    handleVoiceCallCreated(
      callMessage({ callSid: 'CALLX1', voiceAgent: false }),
      1,
      'online'
    );

    expect(ringing()).toEqual(['CALLX1']);
  });

  it('rings once the call is handed back from the voice agent', () => {
    const commit = vi.fn();
    handleVoiceCallUpdated(
      commit,
      callMessage({ callSid: 'CALLAI2', voiceAgent: true }),
      1,
      'online'
    );
    expect(ringing()).toEqual([]);

    handleVoiceCallUpdated(
      commit,
      callMessage({ callSid: 'CALLAI2', voiceAgent: false }),
      1,
      'online'
    );

    expect(ringing()).toEqual(['CALLAI2']);
  });
});
