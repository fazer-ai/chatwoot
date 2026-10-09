import { readonly, ref } from 'vue';
import Cookies from 'js-cookie';
import WhatsappCallsAPI from 'dashboard/api/channel/whatsapp/whatsappCallsAPI';
import { remuxWebmToOgg } from 'dashboard/components/widgets/WootWriter/utils/webmOpusToOgg';
import { VOICE_CALL_OUTBOUND_INIT_STATUS } from 'dashboard/components-next/message/constants';
import { useCallsStore } from 'dashboard/stores/calls';
import { markCallDismissed } from 'dashboard/helper/voice';

// Module-level state lets the cable handlers and unload listeners reach the
// live PeerConnection without prop-drilling refs through every composable.
let pc = null;
let localStream = null;
let remoteStream = null;
let remoteAudioEl = null;
let mediaRecorder = null;
let recorderChunks = [];
let audioContext = null;
let activeCallId = null;
// The provider's id of the call this tab placed, which is what a late ringing message names.
let activeCallSid = null;
// voice_call.outbound_connected (the sole source of the outbound SDP answer) is
// broadcast account-wide and can arrive before the /initiate response sets
// activeCallId in this tab. Until we know our own call id we can't tell our
// answer from a concurrent agent's, so the cable handler buffers them here keyed
// by call id (a single slot would let a concurrent agent's event clobber ours)
// and initiateOutboundCall flushes the matching one by id.
const pendingOutboundAnswers = new Map();
// The pickup and the end of a placed call are broadcast too, and on a paired phone they
// can arrive before this tab has the call in its store: the connector answers the dial as
// soon as the phone rings. They are kept here by call id, like the answers above, and
// applied by the calls store when the call is added (takeEarlyOutboundOutcome).
const earlyOutboundOutcomes = new Map();
// Module-scoped so multiple composable callers (header button + contact-panel
// button) share the same lock. A per-instance ref let two parallel callers
// both pass the guard and tear down each other's WebRTC state in cleanup().
// ref() so consumers can reactively gate buttons on it (the composable
// re-exports this as `isInitiating`).
const isInitiatingOutbound = ref(false);
const isInitiatingOutboundReadonly = readonly(isInitiatingOutbound);
// Inbound calls record from the moment the agent clicks accept (their click =
// pickup). Outbound calls must wait — Meta's `connect` webhook (which lands
// during ringing) negotiates remote tracks ~20s before the contact actually
// answers, and we don't want pre-pickup audio in the recording. This flag is
// flipped to true by armOutboundRecorder() when the ACCEPTED status arrives.
let recorderArmed = false;
// This call's recording decision, snapshotted server-side at call creation and
// carried on every payload that can start a call in this tab.
let callRecordingEnabled = true;

const ensureRemoteAudioElement = () => {
  if (remoteAudioEl) return remoteAudioEl;
  remoteAudioEl = document.createElement('audio');
  remoteAudioEl.id = 'whatsapp-call-remote-audio';
  remoteAudioEl.autoplay = true;
  remoteAudioEl.playsInline = true;
  remoteAudioEl.style.display = 'none';
  document.body.appendChild(remoteAudioEl);
  return remoteAudioEl;
};

const playRemoteStream = stream => {
  const el = ensureRemoteAudioElement();
  el.srcObject = stream;
  el.play().catch(err => {
    // eslint-disable-next-line no-console
    console.warn('[WhatsApp Call] remote audio play() failed:', err);
  });
};

// 1s timeslice keeps a recent recording chunk in memory so a remote hangup
// that races cleanup still has data to upload.
const RECORDING_TIMESLICE_MS = 1000;
const ICE_GATHER_TIMEOUT_MS = 10000;
// The OGG remux is a whole-file in-memory pass on the main thread (~4x the
// blob size transient); past this cap (~3 h at the 48 kbps recording bitrate)
// skip it and upload the raw WebM instead.
const MAX_REMUX_BYTES = 64 * 1024 * 1024;

const RECORDER_MIME_CANDIDATES = [
  'audio/webm;codecs=opus',
  'audio/webm',
  'audio/ogg;codecs=opus',
];

// Outbound calls have no backend-supplied ice_servers (the call doesn't exist
// at offer time). Without STUN the browser only sends host candidates and
// browser→Meta media silently drops through any non-trivial NAT.
const DEFAULT_OUTBOUND_ICE_SERVERS = [{ urls: 'stun:stun.l.google.com:19302' }];

const waitForIceGatheringComplete = peer =>
  new Promise(resolve => {
    if (peer.iceGatheringState === 'complete') {
      resolve();
      return;
    }
    const timer = setTimeout(resolve, ICE_GATHER_TIMEOUT_MS);
    peer.addEventListener('icegatheringstatechange', () => {
      if (peer.iceGatheringState === 'complete') {
        clearTimeout(timer);
        resolve();
      }
    });
  });

const setupRecorder = () => {
  if (!callRecordingEnabled) return;
  if (!localStream || !remoteStream || mediaRecorder) return;
  // createMediaStreamSource on a stream with no audio tracks wires up to
  // nothing — the recorded mix would be silence. Wait until ontrack fires.
  if (remoteStream.getAudioTracks().length === 0) return;

  audioContext = new AudioContext({ sampleRate: 48000 });
  // AudioContext starts suspended under most autoplay policies; without
  // resume() the destination stream produces silence.
  audioContext.resume().catch(() => {});

  const destination = audioContext.createMediaStreamDestination();
  audioContext.createMediaStreamSource(localStream).connect(destination);
  audioContext.createMediaStreamSource(remoteStream).connect(destination);

  const mimeType = RECORDER_MIME_CANDIDATES.find(t =>
    MediaRecorder.isTypeSupported(t)
  );
  if (!mimeType) return;

  recorderChunks = [];
  // 48 kbps Opus is transparent for speech vs Chrome's ~128 kbps default.
  mediaRecorder = new MediaRecorder(destination.stream, {
    mimeType,
    audioBitsPerSecond: 48000,
  });
  mediaRecorder.ondataavailable = event => {
    if (event.data && event.data.size > 0) recorderChunks.push(event.data);
  };
  mediaRecorder.start(RECORDING_TIMESLICE_MS);
};

const cleanup = () => {
  if (mediaRecorder && mediaRecorder.state !== 'inactive') {
    try {
      mediaRecorder.stop();
    } catch (_) {
      /* noop */
    }
  }
  if (audioContext && audioContext.state !== 'closed') {
    audioContext.close().catch(() => {});
  }
  if (localStream) localStream.getTracks().forEach(t => t.stop());
  if (remoteStream) remoteStream.getTracks().forEach(t => t.stop());
  if (pc) pc.close();
  if (remoteAudioEl) remoteAudioEl.srcObject = null;

  pc = null;
  // Outcomes are kept through a teardown: an end that tore the session down while the
  // dial was still being answered is what keeps the call it placed from being added
  // back as ringing. A new dial starts them over.
  localStream = null;
  remoteStream = null;
  mediaRecorder = null;
  callRecordingEnabled = true;
  recorderChunks = [];
  audioContext = null;
  activeCallId = null;
  activeCallSid = null;
  pendingOutboundAnswers.clear();
  recorderArmed = false;
  // eslint-disable-next-line no-use-before-define
  stopRingingTimer();
};

const buildPeerConnection = iceServers => {
  const config = iceServers && iceServers.length ? { iceServers } : {};
  pc = new RTCPeerConnection(config);
  remoteStream = new MediaStream();
  pc.ontrack = event => {
    // Reuse the same MediaStream object — the recorder's audioContext source
    // taps it once, so reassigning would orphan the recorder.
    const tracks =
      event.streams && event.streams[0]
        ? event.streams[0].getTracks()
        : [event.track];
    tracks.forEach(track => {
      if (!remoteStream.getTracks().includes(track))
        remoteStream.addTrack(track);
    });
    playRemoteStream(remoteStream);
    // Only arm the recorder when the call is actually accepted. For outbound
    // this is the ACCEPTED status webhook; for inbound this is the agent's
    // own click (acceptIncomingCall flips recorderArmed before returning).
    if (recorderArmed) setupRecorder();
  };
  // A transport that failed carries nothing more, and the provider may never say the call
  // ended: a paired phone's connector hangs up a call it can no longer carry without
  // always reaching the client.
  const own = pc;
  own.onconnectionstatechange = () => {
    if (own !== pc || own.connectionState !== 'failed' || !activeCallId) return;
    // eslint-disable-next-line no-use-before-define
    letGoOfCall(activeCallId, activeCallSid);
  };
  return pc;
};

// A call this tab can no longer expect to hear the end of. The end is asked for, as an
// agent hanging up would, and this tab lets go of the call itself whether or not that went
// through: the end broadcast is not replayed to a tab whose cable was down, and a failed
// request sends none. The recording is uploaded, the session released and the card
// removed, once, however many of these and the broadcast arrive.
const letGoOfCall = (callId, placedSid) =>
  WhatsappCallsAPI.terminate(callId)
    .catch(() => {})
    .then(() => {
      if (activeCallId !== callId) return undefined;
      // eslint-disable-next-line no-use-before-define
      return handleWhatsappRemoteEnd(callId).catch(() => {});
    })
    .then(() => {
      const store = useCallsStore();
      const card = store.calls.find(c => c.callId === callId);
      // Dismissed as an end broadcast would, so a ringing message still queued for the
      // call does not add it back.
      markCallDismissed(card?.callSid || placedSid);
      if (card) store.removeCall(card.callSid);
    });

// WhatsApp stops ringing an unanswered call well within this. A placed call still
// ringing past it lost its end on the way: a paired phone's connector that lost its
// session ends its calls without always reaching the client, and before the callee
// answers there is no transport yet whose failure would say so.
export const OUTBOUND_RINGING_LIMIT_MS = 90 * 1000;
let ringingTimer = null;

const stopRingingTimer = () => {
  if (ringingTimer) clearTimeout(ringingTimer);
  ringingTimer = null;
};

const startRingingTimer = (callId, placedSid) => {
  stopRingingTimer();
  ringingTimer = setTimeout(() => {
    ringingTimer = null;
    if (activeCallId === callId) letGoOfCall(callId, placedSid);
  }, OUTBOUND_RINGING_LIMIT_MS);
};

const stopRecorderAndUpload = async callId => {
  if (mediaRecorder && mediaRecorder.state !== 'inactive') {
    await new Promise(resolve => {
      mediaRecorder.addEventListener('stop', resolve, { once: true });
      try {
        mediaRecorder.stop();
      } catch (_) {
        resolve();
      }
    });
  }
  if (!recorderChunks.length || !callId) return;

  let blob = new Blob(recorderChunks, { type: recorderChunks[0].type });
  const isWebm = blob.type.startsWith('audio/webm');
  let filename = isWebm ? 'call-recording.webm' : 'call-recording.ogg';
  // Remux to OGG so the file carries a real duration (MediaRecorder never
  // backfills the WebM duration header, which breaks mobile players).
  if (isWebm && blob.size <= MAX_REMUX_BYTES) {
    try {
      blob = await remuxWebmToOgg(blob);
      filename = 'call-recording.ogg';
    } catch (_) {
      /* noop — fall back to uploading the raw WebM */
    }
  }
  // Best-effort — the controller's idempotency guard handles a retry.
  try {
    await WhatsappCallsAPI.uploadRecording(callId, blob, filename);
  } catch (_) {
    /* noop */
  }
};

// devise-token-auth requires access-token / client / uid headers on every
// request — navigator.sendBeacon can't set custom headers, so we rehydrate
// the auth payload from the cw_d_session_info cookie that the dashboard sets
// at login. Used by the page-close terminate path below.
const getDeviseAuthHeaders = () => {
  try {
    const raw = Cookies.get('cw_d_session_info');
    if (!raw) return null;
    const session = JSON.parse(raw);
    return {
      'access-token': session['access-token'] || '',
      client: session.client || '',
      uid: session.uid || '',
      expiry: session.expiry || '',
      'token-type': session['token-type'] || 'Bearer',
    };
  } catch (_) {
    return null;
  }
};

const beaconTerminate = callId => {
  if (!callId) return;
  const accountId = window.location.pathname.split('/')[3];
  if (!accountId) return;
  const headers = getDeviseAuthHeaders();
  if (!headers) return;
  const url = `/api/v1/accounts/${accountId}/whatsapp_calls/${callId}/terminate`;
  // fetch+keepalive (instead of navigator.sendBeacon) so we can attach auth
  // headers — without them devise-token-auth 401s and the call stays open on
  // Meta until its carrier-side timeout (~60s).
  try {
    fetch(url, {
      method: 'POST',
      keepalive: true,
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json', ...headers },
      body: '{}',
    }).catch(() => {});
  } catch (_) {
    /* noop */
  }
};

export const hasActiveWhatsappCall = () => !!(activeCallId || pc);

export const isLocalWhatsappCall = callId =>
  !!callId && activeCallId != null && callId === activeCallId;

export function useWhatsappCallSession() {
  const prepareInboundAnswer = async (sdpOffer, iceServers) => {
    cleanup();
    localStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    buildPeerConnection(iceServers);
    localStream.getTracks().forEach(t => pc.addTrack(t, localStream));
    await pc.setRemoteDescription({ type: 'offer', sdp: sdpOffer });
    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await waitForIceGatheringComplete(pc);
    return pc.localDescription.sdp;
  };

  const prepareOutboundOffer = async () => {
    cleanup();
    localStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    buildPeerConnection(DEFAULT_OUTBOUND_ICE_SERVERS);
    localStream.getTracks().forEach(t => pc.addTrack(t, localStream));
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await waitForIceGatheringComplete(pc);
    return pc.localDescription.sdp;
  };

  const acceptIncomingCall = async ({
    callId,
    sdpOffer,
    iceServers,
    recordingEnabled,
  }) => {
    // The store may not have sdpOffer yet (the cable broadcast can race the
    // click). Fall back to GET /whatsapp_calls/:id which exposes it.
    let offer = sdpOffer;
    let ice = iceServers;
    let recording = recordingEnabled;
    if (!offer && callId) {
      try {
        const fresh = await WhatsappCallsAPI.show(callId);
        offer = fresh?.sdp_offer || fresh?.sdpOffer;
        ice = ice || fresh?.ice_servers || fresh?.iceServers;
        recording = recording ?? fresh?.recording_enabled;
      } catch (e) {
        // eslint-disable-next-line no-console
        console.error(
          '[WhatsApp Call] failed to fetch call data for accept:',
          e
        );
      }
    }
    if (!offer) {
      throw new Error('Missing sdp_offer for accept — call may have ended.');
    }

    // Release the mic + peer connection if anything between here and the accept
    // round-trip fails — otherwise a rejected accept leaves the mic live and
    // activeCallId set. Mirrors rejectIncomingCall's self-cleanup; rethrow so
    // the caller can surface the failure and skip marking the call active.
    try {
      const sdpAnswer = await prepareInboundAnswer(offer, ice);
      activeCallId = callId;
      // Inbound: agent's click is the pickup. Arm the recorder before the API
      // round-trip so when ontrack fires (triggered by setRemoteDescription
      // back in prepareInboundAnswer) the recorder is already authorized.
      callRecordingEnabled = recording !== false;
      recorderArmed = true;
      setupRecorder();
      await WhatsappCallsAPI.accept(callId, sdpAnswer);
    } catch (e) {
      cleanup();
      throw e;
    }
  };

  const rejectIncomingCall = async callId => {
    try {
      await WhatsappCallsAPI.reject(callId);
    } finally {
      cleanup();
    }
  };

  // target: { conversationId } or { contactId, inboxId }
  const initiateOutboundCall = async target => {
    // Module-scoped lock + active-session guard so a second click — from the
    // same composable instance OR a different one (header vs contact panel)
    // OR while a call is already live — can't tear down the in-flight setup
    // via prepareOutboundOffer's cleanup().
    if (isInitiatingOutbound.value)
      return { status: VOICE_CALL_OUTBOUND_INIT_STATUS.LOCKED };
    if (hasActiveWhatsappCall())
      return { status: VOICE_CALL_OUTBOUND_INIT_STATUS.LOCKED };
    isInitiatingOutbound.value = true;
    earlyOutboundOutcomes.clear();
    try {
      const sdpOffer = await prepareOutboundOffer();
      const response = await WhatsappCallsAPI.initiate(target, sdpOffer);
      if (response?.id) {
        activeCallId = response.id;
        activeCallSid = response.call_id || null;
        startRingingTimer(activeCallId, activeCallSid);
        callRecordingEnabled = response.recording_enabled !== false;
        // A connect webhook that raced ahead of this response was buffered;
        // apply our own by id now that we know it, then drop every buffered
        // answer (concurrent agents' calls aren't ours to apply).
        const buffered = pendingOutboundAnswers.get(activeCallId);
        pendingOutboundAnswers.clear();
        if (buffered) {
          await pc.setRemoteDescription({
            type: 'answer',
            sdp: buffered,
          });
        }
        return response;
      }
      // No call id back: this is the permission-request branch. The mic +
      // PeerConnection allocated by prepareOutboundOffer aren't useful until
      // the contact opts in and the agent retries — release them.
      cleanup();
      return response;
    } catch (e) {
      cleanup();
      // BE returns 422 when the contact hasn't opted in (permission template
      // sent or already pending). Surface it to the caller as a normal
      // response shape so it can render the banner instead of an error toast.
      const data = e?.response?.data;
      if (
        data?.status === VOICE_CALL_OUTBOUND_INIT_STATUS.PERMISSION_REQUESTED ||
        data?.status === VOICE_CALL_OUTBOUND_INIT_STATUS.PERMISSION_PENDING
      ) {
        return { status: data.status, conversation_id: data.conversation_id };
      }
      throw e;
    } finally {
      isInitiatingOutbound.value = false;
    }
  };

  // callIdOverride is the call.id from the dashboard's calls store. Module
  // `activeCallId` may be null after a prior accept attempt's cleanup() — but
  // the call still exists on Meta and must still be terminated. Falling back
  // to the override means hangup is robust to a wiped local session.
  const endActiveCall = async (callIdOverride = null) => {
    const callId = activeCallId || callIdOverride;
    if (!callId) {
      cleanup();
      return;
    }
    try {
      // Terminate on Meta first so the contact is disconnected immediately. The
      // recording upload below can be slow on long calls or poor networks, and
      // the peer connection / mic must not stay live for the contact during it.
      await WhatsappCallsAPI.terminate(callId).catch(() => {});
      await stopRecorderAndUpload(callId);
    } finally {
      cleanup();
    }
  };

  return {
    isInitiating: isInitiatingOutboundReadonly,
    prepareInboundAnswer,
    prepareOutboundOffer,
    acceptIncomingCall,
    rejectIncomingCall,
    initiateOutboundCall,
    endActiveCall,
  };
}

// Cable handlers fire outside any composable instance, so the shared session
// surface is exposed as module-level functions for them.

export const applyOutboundAnswer = async (callId, sdpAnswer) => {
  // No in-flight peer connection in this tab → not our call.
  if (!pc) return;
  // /initiate hasn't returned our call id yet (the connect webhook raced
  // ahead). Buffer the answer; initiateOutboundCall flushes it by id once it
  // knows which call is ours, so a concurrent agent's answer is never applied.
  if (activeCallId == null) {
    pendingOutboundAnswers.set(callId, sdpAnswer);
    return;
  }
  // activeCallId known → only apply the answer for this tab's call.
  if (callId !== activeCallId) return;
  await pc.setRemoteDescription({ type: 'answer', sdp: sdpAnswer });
};

// Called by the cable handler when Meta delivers status=ACCEPTED for the
// outbound call (real pickup). Flips the recorder gate and starts the
// MediaRecorder. Idempotent — safe if ontrack hasn't fired yet (setupRecorder
// bails until the remote stream has audio tracks; ontrack will retry).
export const armOutboundRecorder = () => {
  // Picked up: from here a lost call is the transport's to report.
  stopRingingTimer();
  recorderArmed = true;
  setupRecorder();
};

export const cleanupWhatsappSession = () => cleanup();

// outcome: 'accepted' or 'ended'. Kept only while this tab is placing a call whose id it
// does not know yet, or knows and has not added yet; anything else is not this tab's.
export const noteEarlyOutboundOutcome = (callId, outcome) => {
  if (!pc || (activeCallId != null && activeCallId !== callId)) return;
  if (earlyOutboundOutcomes.get(callId) === 'ended') return;
  earlyOutboundOutcomes.set(callId, outcome);
};

// An end alone, for a call this tab no longer owns: a session torn down by the end of
// the call it was placing. Any other outcome stays where it is.
export const takeEarlyOutboundEnd = callId => {
  if (earlyOutboundOutcomes.get(callId) !== 'ended') return undefined;
  earlyOutboundOutcomes.delete(callId);
  return 'ended';
};

export const takeEarlyOutboundOutcome = callId => {
  const outcome = earlyOutboundOutcomes.get(callId);
  earlyOutboundOutcomes.delete(callId);
  return outcome;
};

// One end of a call can be asked for twice: by its broadcast, and by the store adding a
// call whose end it kept. The second waits for the first instead of tearing down the
// recorder whose upload the first is still finishing.
let ending = null;

export const handleWhatsappRemoteEnd = callId => {
  // Snapshot before cleanup nulls activeCallId.
  const id = callId || activeCallId;
  if (!id) {
    cleanup();
    return Promise.resolve();
  }
  if (ending?.id === id) return ending.promise;
  const promise = (async () => {
    try {
      await stopRecorderAndUpload(id);
    } finally {
      cleanup();
      ending = null;
    }
  })();
  ending = { id, promise };
  return promise;
};

export const setWhatsappCallMuted = muted => {
  if (!localStream) return false;
  localStream.getAudioTracks().forEach(track => {
    track.enabled = !muted;
  });
  return muted;
};

export const sendWhatsappTerminateBeacon = () => {
  // Always fire when there's a live callId. The beacon endpoint is idempotent,
  // so racing it with an in-flight Axios terminate (which unload may abort) is
  // fine — Meta gets exactly one terminate either way, and we avoid leaving
  // the call ringing on Meta until its carrier-side timeout.
  if (!activeCallId) return;
  beaconTerminate(activeCallId);
};
