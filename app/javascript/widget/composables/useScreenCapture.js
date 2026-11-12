import { IFrameHelper } from 'widget/helpers/utils';

// Time the host page needs to repaint without the widget before the frame is taken.
const HIDE_DELAY_MS = 300;
const FRAME_TIMEOUT_MS = 3000;

const CANCEL_ERRORS = ['NotAllowedError', 'AbortError'];

const wait = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

// The SDK hides the widget iframe, where requestAnimationFrame can stop, so the frame
// comes from ImageCapture or, where it does not exist, from a playing <video>.
const grabFrame = async track => {
  if (window.ImageCapture) return new window.ImageCapture(track).grabFrame();

  const video = document.createElement('video');
  video.muted = true;
  video.srcObject = new MediaStream([track]);
  await Promise.race([
    video.play(),
    wait(FRAME_TIMEOUT_MS).then(() => {
      throw new Error('Timed out waiting for the screen frame');
    }),
  ]);
  return video;
};

const frameToFile = frame => {
  const canvas = document.createElement('canvas');
  canvas.width = frame.videoWidth || frame.width;
  canvas.height = frame.videoHeight || frame.height;
  canvas.getContext('2d').drawImage(frame, 0, 0);
  frame.close?.();
  return new Promise(resolve => {
    canvas.toBlob(blob => {
      resolve(
        new File([blob], `screenshot-${Date.now()}.png`, { type: 'image/png' })
      );
    }, 'image/png');
  });
};

export function useScreenCapture() {
  const isScreenCaptureSupported = Boolean(
    navigator.mediaDevices?.getDisplayMedia
  );

  // Resolves with a PNG File, or with null when the user closes the picker.
  const captureScreen = async () => {
    let stream;
    try {
      // Called first, while the click still counts as a user gesture.
      stream = await navigator.mediaDevices.getDisplayMedia({
        video: true,
        audio: false,
        preferCurrentTab: true,
        selfBrowserSurface: 'include',
      });
    } catch (error) {
      if (CANCEL_ERRORS.includes(error.name)) return null;
      throw error;
    }

    const isEmbedded = IFrameHelper.isIFrame();
    try {
      if (isEmbedded) {
        IFrameHelper.sendMessage({ event: 'closeWindow' });
        await wait(HIDE_DELAY_MS);
      }
      const [track] = stream.getVideoTracks();
      return await frameToFile(await grabFrame(track));
    } finally {
      stream.getTracks().forEach(track => track.stop());
      if (isEmbedded) IFrameHelper.sendMessage({ event: 'toggleBubble' });
    }
  };

  return { isScreenCaptureSupported, captureScreen };
}
