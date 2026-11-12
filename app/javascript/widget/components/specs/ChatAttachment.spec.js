import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import FileUpload from 'vue-upload-component';
import ChatAttachment from '../ChatAttachment.vue';

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
      getters: { getShouldShowFilePicker: () => true },
    },
  },
});

const upload = file => ({ file, name: file.name, type: file.type });
const photo = new File(['png'], 'photo.png', { type: 'image/png' });

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
    navigator.mediaDevices = undefined;
  });

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

  it('uploads documents and GIFs without the editor', async () => {
    const wrapper = mountAttachment();
    const pdf = new File(['pdf'], 'invoice.pdf', { type: 'application/pdf' });
    const gif = new File(['gif'], 'loop.gif', { type: 'image/gif' });

    await selectFile(wrapper, pdf);
    await selectFile(wrapper, gif);

    expect(wrapper.findComponent({ name: 'ImageEditor' }).exists()).toBe(false);
    expect(onAttach.mock.calls.map(([{ file }]) => file)).toEqual([pdf, gif]);
  });

  it('shows the capture button only when the browser can capture the screen', () => {
    const label = '[aria-label="SCREEN_CAPTURE.BUTTON"]';
    expect(mountAttachment().find(label).exists()).toBe(false);

    navigator.mediaDevices = { getDisplayMedia: vi.fn() };
    expect(mountAttachment().find(label).exists()).toBe(true);
  });
});
