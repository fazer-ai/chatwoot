import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import ChatInputWrap from '../ChatInputWrap.vue';

const store = createStore({
  modules: {
    appConfig: {
      namespaced: true,
      getters: {
        getWidgetColor: () => '#1f93ff',
        getIsWidgetOpen: () => false,
        getShouldShowEmojiPicker: () => false,
        getShouldShowFilePicker: () => true,
      },
    },
    conversation: {
      namespaced: true,
      actions: { toggleUserTyping: () => {} },
    },
  },
});

const photo = { file: 'blob-1', thumbUrl: 'blob:1', fileType: 'image' };
const invoice = { file: 'blob-2', thumbUrl: 'blob:2', fileType: 'file' };

describe('ChatInputWrap', () => {
  let onSendAttachment;
  let onSendMessage;

  const mountInput = () =>
    mount(ChatInputWrap, {
      props: { onSendAttachment, onSendMessage },
      global: {
        plugins: [store],
        stubs: { ChatAttachmentButton: true, ChatSendButton: true },
        directives: { onClickaway: {} },
      },
    });

  const attach = async (wrapper, attachment) => {
    wrapper.findComponent({ name: 'ChatAttachmentButton' }).props('onAttach')(
      attachment
    );
    await flushPromises();
  };

  beforeEach(() => {
    onSendAttachment = vi.fn();
    onSendMessage = vi.fn();
    window.chatwootWebChannel = {
      enabledFeatures: ['attachments'],
      sendAttachmentsWithMessage: false,
    };
  });

  it('sends each attachment at once by default', async () => {
    const wrapper = mountInput();

    await attach(wrapper, photo);

    expect(onSendAttachment).toHaveBeenCalledWith([photo]);
  });

  it('holds attachments and sends them with the text when the inbox asks for it', async () => {
    window.chatwootWebChannel.sendAttachmentsWithMessage = true;
    const wrapper = mountInput();

    await attach(wrapper, photo);
    await attach(wrapper, invoice);
    await wrapper.find('textarea').setValue('  see the screen ');

    expect(onSendAttachment).not.toHaveBeenCalled();
    expect(
      wrapper.findComponent({ name: 'ChatAttachmentButton' }).exists()
    ).toBe(true);

    await wrapper.findAll('li button')[1].trigger('click');
    wrapper.findComponent({ name: 'ChatSendButton' }).vm.$emit('click');
    await flushPromises();

    expect(onSendAttachment).toHaveBeenCalledWith([photo], 'see the screen');
    expect(onSendMessage).not.toHaveBeenCalled();
    expect(wrapper.find('li').exists()).toBe(false);
  });

  it('waits for an attachment still uploading before it sends', async () => {
    window.chatwootWebChannel.sendAttachmentsWithMessage = true;
    const wrapper = mountInput();
    const attachment = wrapper.findComponent({ name: 'ChatAttachmentButton' });

    attachment.vm.$emit('uploadsChange', 1);
    await wrapper.find('textarea').setValue('see the invoice');
    wrapper.findComponent({ name: 'ChatSendButton' }).vm.$emit('click');
    expect(onSendMessage).not.toHaveBeenCalled();

    attachment.vm.$emit('uploadsChange', 0);
    await attach(wrapper, invoice);
    wrapper.findComponent({ name: 'ChatSendButton' }).vm.$emit('click');
    expect(onSendAttachment).toHaveBeenCalledWith([invoice], 'see the invoice');
  });
});
