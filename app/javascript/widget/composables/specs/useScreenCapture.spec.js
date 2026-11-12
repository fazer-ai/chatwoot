import { IFrameHelper } from 'widget/helpers/utils';
import { useScreenCapture } from '../useScreenCapture';

vi.mock('widget/helpers/utils', () => ({
  IFrameHelper: { isIFrame: vi.fn(), sendMessage: vi.fn() },
}));

describe('useScreenCapture', () => {
  const track = { stop: vi.fn() };
  const stream = { getVideoTracks: () => [track], getTracks: () => [track] };
  const calls = [];

  beforeEach(() => {
    calls.length = 0;
    vi.useFakeTimers();
    IFrameHelper.isIFrame.mockReturnValue(true);
    IFrameHelper.sendMessage.mockImplementation(({ event }) =>
      calls.push(event)
    );
    track.stop.mockImplementation(() => calls.push('stop'));
    navigator.mediaDevices = {
      getDisplayMedia: vi.fn(async () => {
        calls.push('getDisplayMedia');
        return stream;
      }),
    };
    window.ImageCapture = function ImageCapture() {
      return {
        grabFrame: async () => {
          calls.push('grabFrame');
          return { width: 1280, height: 720, close: vi.fn() };
        },
      };
    };
    vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue({
      drawImage: vi.fn(),
    });
    HTMLCanvasElement.prototype.toBlob = function toBlob(callback, type) {
      callback(new Blob(['frame'], { type }));
    };
  });

  afterEach(() => vi.useRealTimers());

  it('asks for the screen first, hides the widget for the frame and reopens it', async () => {
    const { captureScreen } = useScreenCapture();

    const result = captureScreen();
    await vi.runAllTimersAsync();
    const file = await result;

    expect(calls).toEqual([
      'getDisplayMedia',
      'closeWindow',
      'grabFrame',
      'stop',
      'toggleBubble',
    ]);
    expect(file.type).toBe('image/png');
    expect(file.name).toMatch(/^screenshot-\d+\.png$/);
  });

  it('resolves with null and leaves the widget alone when the picker is closed', async () => {
    navigator.mediaDevices.getDisplayMedia.mockRejectedValue(
      new DOMException('Permission denied', 'NotAllowedError')
    );
    const { captureScreen } = useScreenCapture();

    expect(await captureScreen()).toBeNull();
    expect(IFrameHelper.sendMessage).not.toHaveBeenCalled();
  });

  it('reopens the widget and stops the stream when the frame fails', async () => {
    window.ImageCapture = function ImageCapture() {
      return {
        grabFrame: async () => {
          throw new DOMException('Track ended', 'InvalidStateError');
        },
      };
    };
    const { captureScreen } = useScreenCapture();

    const result = captureScreen();
    const assertion = expect(result).rejects.toThrow('Track ended');
    await vi.runAllTimersAsync();
    await assertion;

    expect(calls).toEqual([
      'getDisplayMedia',
      'closeWindow',
      'stop',
      'toggleBubble',
    ]);
  });
});
