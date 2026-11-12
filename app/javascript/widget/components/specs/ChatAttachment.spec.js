import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import FileUpload from 'vue-upload-component';
import ChatAttachment from '../ChatAttachment.vue';
import { useScreenCapture } from '../../composables/useScreenCapture';

vi.mock('../../composables/useScreenCapture', () => ({
  useScreenCapture: vi.fn(),
}));

const store = createStore({
  modules: {
    globalConfig: {
      namespaced: true,
      getters: {
        get: () => ({ directUploadsEnabled: false, maximumFileUploadSize: 40 }),
      },
    },
    appConfig: {
      namespaced: true,
      getters: {
        getShouldShowFilePicker: () => true,
        getWidgetColor: () => '#1f93ff',
        darkMode: () => 'light',
      },
    },
  },
});

const upload = file => ({ file, name: file.name, type: file.type });
const photo = new File(['png'], 'photo.png', { type: 'image/png' });
const screenshot = new File(['png'], 'screenshot.png', { type: 'image/png' });

describe('ChatAttachment', () => {
  let onAttach;

  const mountAttachment = () =>
    mount(ChatAttachment, {
      props: { onAttach },
      global: { plugins: [store], stubs: { ImageEditor: true } },
    });

  const selectFile = async (wrapper, file) => {
    wrapper.findComponent(FileUpload).vm.$emit('inputFile', upload(file));
    await flushPromises();
  };

  beforeEach(() => {
    onAttach = vi.fn();
    window.URL.createObjectURL = vi.fn(() => 'blob:preview');
    window.chatwootWebChannel = {
      attachmentEditorEnabled: true,
      screenCaptureEnabled: true,
      screenCaptureEditorEnabled: true,
    };
    useScreenCapture.mockReturnValue({
      isScreenCaptureSupported: true,
      captureScreen: vi.fn(async () => screenshot),
    });
  });

  const captureButton = '[aria-label="SCREEN_CAPTURE.BUTTON"]';

  it('opens the editor for an image and uploads the edited file on save', async () => {
    const wrapper = mountAttachment();
    const edited = new File(['edited'], 'photo.png', { type: 'image/png' });

    await selectFile(wrapper, photo);
    const editor = wrapper.findComponent({ name: 'ImageEditor' });

    expect(editor.props('file')).toBe(photo);
    expect(onAttach).not.toHaveBeenCalled();

    editor.vm.$emit('save', edited);
    await flushPromises();

    expect(onAttach).toHaveBeenCalledWith(
      expect.objectContaining({ file: edited, fileType: 'image' })
    );
    expect(wrapper.findComponent({ name: 'ImageEditor' }).exists()).toBe(false);
  });

  it('discards the image when the editor is cancelled', async () => {
    const wrapper = mountAttachment();

    await selectFile(wrapper, photo);
    wrapper.findComponent({ name: 'ImageEditor' }).vm.$emit('cancel');
    await flushPromises();

    expect(wrapper.findComponent({ name: 'ImageEditor' }).exists()).toBe(false);
    expect(onAttach).not.toHaveBeenCalled();
  });

  it('shows the images of a multi-file paste one after the other', async () => {
    const wrapper = mountAttachment();
    const second = new File(['png'], 'second.png', { type: 'image/png' });
    const editor = () => wrapper.findComponent({ name: 'ImageEditor' });

    await selectFile(wrapper, photo);
    await selectFile(wrapper, second);
    expect(editor().props('file')).toBe(photo);

    editor().vm.$emit('cancel');
    await flushPromises();
    expect(editor().props('file')).toBe(second);

    editor().vm.$emit('save', second);
    await flushPromises();
    expect(editor().exists()).toBe(false);
    expect(onAttach.mock.calls.map(([{ file }]) => file)).toEqual([second]);
  });

  it('uploads documents and GIFs without the editor', async () => {
    const wrapper = mountAttachment();
    const pdf = new File(['pdf'], 'invoice.pdf', { type: 'application/pdf' });
    const gif = new File(['gif'], 'loop.gif', { type: 'image/gif' });

    await selectFile(wrapper, pdf);
    await selectFile(wrapper, gif);

    expect(wrapper.findComponent({ name: 'ImageEditor' }).exists()).toBe(false);
    expect(onAttach.mock.calls.map(([{ file }]) => file)).toEqual([pdf, gif]);
  });

  it('uploads images directly when the inbox turns the editor off', async () => {
    window.chatwootWebChannel.attachmentEditorEnabled = false;
    const wrapper = mountAttachment();

    await selectFile(wrapper, photo);

    expect(wrapper.findComponent({ name: 'ImageEditor' }).exists()).toBe(false);
    expect(onAttach).toHaveBeenCalledWith(
      expect.objectContaining({ file: photo })
    );
  });

  it('shows the capture button only when the inbox and the browser allow it', () => {
    expect(mountAttachment().find(captureButton).exists()).toBe(true);

    window.chatwootWebChannel.screenCaptureEnabled = false;
    expect(mountAttachment().find(captureButton).exists()).toBe(false);

    window.chatwootWebChannel.screenCaptureEnabled = true;
    useScreenCapture.mockReturnValue({ isScreenCaptureSupported: false });
    expect(mountAttachment().find(captureButton).exists()).toBe(false);
  });

  it('opens the screenshot in the editor, or sends it when the inbox turns the editor off', async () => {
    const wrapper = mountAttachment();
    await wrapper.find(captureButton).trigger('click');
    await flushPromises();
    expect(wrapper.findComponent({ name: 'ImageEditor' }).props('file')).toBe(
      screenshot
    );

    window.chatwootWebChannel.screenCaptureEditorEnabled = false;
    const direct = mountAttachment();
    await direct.find(captureButton).trigger('click');
    await flushPromises();
    expect(direct.findComponent({ name: 'ImageEditor' }).exists()).toBe(false);
    expect(onAttach).toHaveBeenCalledWith(
      expect.objectContaining({ file: screenshot })
    );
  });
});
