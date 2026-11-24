import { defineComponent, ref } from 'vue';
import { mount } from '@vue/test-utils';
import VideoNoteBubble from '../VideoNote.vue';
import { provideMessageContext } from '../../provider.js';
import { MESSAGE_VARIANTS, ORIENTATION } from '../../constants';

vi.mock('dashboard/composables/loadWithRetry', async () => {
  const { ref: vueRef } = await import('vue');
  return {
    useLoadWithRetry: () => ({
      isLoaded: vueRef(true),
      hasError: vueRef(false),
      loadWithRetry: vi.fn(),
    }),
  };
});

const mountVideoNote = () => {
  const TestHost = defineComponent({
    components: { VideoNoteBubble },
    setup() {
      provideMessageContext({
        attachments: ref([
          { fileType: 'video', dataUrl: 'note.mp4', isVideoNote: true },
        ]),
        variant: ref(MESSAGE_VARIANTS.USER),
        orientation: ref(ORIENTATION.LEFT),
        contentAttributes: ref({}),
        additionalAttributes: ref({}),
        shouldGroupWithNext: ref(false),
        inReplyTo: ref(null),
        id: ref(1),
        sender: ref({}),
        senderType: ref('contact'),
      });
    },
    template: '<VideoNoteBubble />',
  });

  return mount(TestHost, {
    global: {
      stubs: {
        MessageMeta: true,
        ReferralCard: true,
        CaptainGenerationDetails: true,
      },
      mocks: { $t: key => key },
    },
  });
};

describe('VideoNote bubble', () => {
  it('plays the file inside a circle, with no bubble behind it', () => {
    const wrapper = mountVideoNote();

    const circle = wrapper.find('button');
    expect(circle.classes()).toContain('rounded-full');
    expect(circle.classes()).toContain('overflow-hidden');
    expect(circle.find('video').attributes('src')).toBe('note.mp4');
    expect(circle.find('video').classes()).toContain('object-cover');
    expect(wrapper.find('[data-bubble-name="video-note"]').classes()).toContain(
      'bg-transparent'
    );
  });

  it('plays on a click and pauses on the next, as on the phone', async () => {
    const wrapper = mountVideoNote();
    const video = wrapper.find('video').element;
    let paused = true;
    Object.defineProperty(video, 'paused', { get: () => paused });
    video.play = vi.fn(() => {
      paused = false;
      return Promise.resolve();
    });
    video.pause = vi.fn(() => {
      paused = true;
    });

    expect(wrapper.find('button').attributes('aria-label')).toBe(
      'COMPONENTS.MEDIA.PLAY_VIDEO_NOTE'
    );
    await wrapper.find('button').trigger('click');
    expect(video.play).toHaveBeenCalledTimes(1);
    await wrapper.find('video').trigger('play');
    expect(wrapper.find('button').attributes('aria-label')).toBe(
      'COMPONENTS.MEDIA.PAUSE_VIDEO_NOTE'
    );

    await wrapper.find('button').trigger('click');
    expect(video.pause).toHaveBeenCalledTimes(1);
  });

  it('handles a refused play, and keeps the play icon', async () => {
    const wrapper = mountVideoNote();
    const video = wrapper.find('video').element;
    Object.defineProperty(video, 'paused', { get: () => true });
    // A refusal changes nothing on the element and fires no error event, so the only
    // trace of it is the promise, which has to be handled or it surfaces as an error.
    let handled = false;
    const refusal = Promise.reject(
      new DOMException('refused', 'NotAllowedError')
    );
    const then = refusal.then.bind(refusal);
    refusal.then = (onFulfilled, onRejected) => {
      if (onRejected) handled = true;
      return then(onFulfilled, onRejected);
    };
    refusal.catch = onRejected => refusal.then(undefined, onRejected);
    // A plain function, not vi.fn: a spy attaches its own handlers to record the result.
    video.play = () => refusal;

    await wrapper.find('button').trigger('click');
    await new Promise(resolve => {
      setTimeout(resolve, 0);
    });

    expect(handled).toBe(true);
    expect(wrapper.find('button').attributes('aria-label')).toBe(
      'COMPONENTS.MEDIA.PLAY_VIDEO_NOTE'
    );
  });
});
