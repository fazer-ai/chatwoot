import TwilioVoiceClient from 'dashboard/api/channel/voice/twilioVoiceClient';
import {
  armOutboundRecorder,
  cleanupWhatsappSession,
  isLocalWhatsappCall,
  takeEarlyOutboundOutcome,
} from 'dashboard/composables/useWhatsappCallSession';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { TERMINAL_STATUSES } from 'dashboard/helper/voice';
import { defineStore } from 'pinia';

const teardownByProvider = call => {
  if (call?.provider === VOICE_CALL_PROVIDERS.WHATSAPP) {
    cleanupWhatsappSession();
  } else {
    TwilioVoiceClient.endClientCall();
  }
};

export const useCallsStore = defineStore('calls', {
  state: () => ({
    calls: [],
  }),

  getters: {
    activeCall: state => state.calls.find(call => call.isActive) || null,
    hasActiveCall: state => state.calls.some(call => call.isActive),
    incomingCalls: state => state.calls.filter(call => !call.isActive),
    hasIncomingCall: state => state.calls.some(call => !call.isActive),
  },

  actions: {
    handleCallStatusChanged({ callSid, status }) {
      if (!TERMINAL_STATUSES.includes(status)) return;

      const call = this.calls.find(c => c.callSid === callSid);
      // WhatsApp recordings live in the in-memory recorder until voice_call.ended
      // uploads them; tearing down here would race-wipe those chunks.
      if (call?.provider === 'whatsapp') {
        this.calls = this.calls.filter(c => c.callSid !== callSid);
        return;
      }

      this.removeCall(callSid);
    },

    addCall(callData) {
      if (!callData?.callSid) return;
      const existing = this.calls.find(c => c.callSid === callData.callSid);
      if (existing) {
        // Merge so a later cable event with sdp_offer/provider/caller fills in
        // gaps left by the earlier message.created path (and vice versa).
        // Preserve a previously-captured caller snapshot when the incoming
        // event has no sender info, otherwise the widget would flip to
        // "Unknown caller" on the next status update.
        const next = { ...callData };
        if (existing.caller && !next.caller) delete next.caller;
        Object.assign(existing, next, { isActive: existing.isActive });
        // The message can add this tab's placed call before the tab does; an outcome kept
        // for it is applied when the tab adds it all the same.
        this.applyEarlyOutcome(callData);
        return;
      }

      // Prepend so the newest call surfaces as the primary card (incomingCalls[0])
      // and older calls drop into the stack below it.
      this.calls.unshift({
        ...callData,
        isActive: false,
      });
      this.applyEarlyOutcome(callData);
    },

    // A call this tab placed that was picked up, or ended, before the tab had it. Only this
    // tab's own call: a sibling tab's, arriving here as a message, is not this tab's to
    // start or to release.
    applyEarlyOutcome(callData) {
      if (
        callData.provider !== VOICE_CALL_PROVIDERS.WHATSAPP ||
        !isLocalWhatsappCall(callData.callId)
      )
        return;
      const early = takeEarlyOutboundOutcome(callData.callId);
      if (early === 'ended') {
        this.calls = this.calls.filter(c => c.callSid !== callData.callSid);
        cleanupWhatsappSession();
      } else if (early === 'accepted') {
        this.setCallActive(callData.callSid);
        armOutboundRecorder();
      }
    },

    removeCall(callSid) {
      const callToRemove = this.calls.find(c => c.callSid === callSid);
      if (callToRemove?.isActive) {
        teardownByProvider(callToRemove);
      }
      this.calls = this.calls.filter(c => c.callSid !== callSid);
    },

    setCallActive(callSid) {
      this.calls = this.calls.map(call => ({
        ...call,
        isActive: call.callSid === callSid,
      }));
    },

    clearActiveCall() {
      const active = this.calls.find(c => c.isActive);
      teardownByProvider(active);
      this.calls = this.calls.filter(call => !call.isActive);
    },

    dismissCall(callSid) {
      this.calls = this.calls.filter(call => call.callSid !== callSid);
    },

    removeCallsForConversation(conversationId) {
      const callsToRemove = this.calls.filter(
        call => call.conversationId === conversationId
      );

      // Tear down each active call via its own provider so a WhatsApp call
      // gets cleanupWhatsappSession() (closes pc, stops recorder/mic) instead
      // of the Twilio-only endClientCall() — otherwise mic stays open.
      callsToRemove.filter(call => call.isActive).forEach(teardownByProvider);

      this.calls = this.calls.filter(
        call => call.conversationId !== conversationId
      );
    },
  },
});
