import { shallowMount } from '@vue/test-utils';
import MessageEditor from '../MessageEditor.vue';

const mockAlert = vi.fn();
vi.mock('dashboard/composables', async () => {
  const actual = await vi.importActual('dashboard/composables');
  return { ...actual, useAlert: (...args) => mockAlert(...args) };
});

const file = (name, type, size) =>
  new File(size ? [new Uint8Array(size)] : [], name, { type });

const mountEditor = () =>
  shallowMount(MessageEditor, {
    global: {
      mocks: { $t: key => key },
      stubs: { WootWriter: true, Icon: true },
    },
  });

// The internal chat composer answered the empty-file question three different ways at once: the
// picker attached a zero-byte file and let the send carry it (attachments here are built outside
// Messages::MessageBuilder, so nothing refuses it on the server either), while paste and drop
// dropped it without a word. None of the three said anything to the person.
describe('MessageEditor attachments', () => {
  // The paste and drop listeners sit on the composer's root element.
  const editor = wrapper => wrapper;
  const attachmentNames = wrapper =>
    wrapper.findAll('.truncate.text-xs').map(node => node.text());

  it('refuses an empty file chosen in the picker instead of attaching it', async () => {
    const wrapper = mountEditor();
    const input = wrapper.find('input[type="file"]');

    Object.defineProperty(input.element, 'files', {
      value: [file('vazio.txt', 'text/plain', 0)],
      configurable: true,
    });
    await input.trigger('change');

    expect(mockAlert).toHaveBeenCalledWith('CONVERSATION.FILE_IS_EMPTY');
    expect(attachmentNames(wrapper)).toEqual([]);
  });

  it('keeps attaching a real file chosen in the picker', async () => {
    const wrapper = mountEditor();
    const input = wrapper.find('input[type="file"]');

    Object.defineProperty(input.element, 'files', {
      value: [file('valido.txt', 'text/plain', 4)],
      configurable: true,
    });
    await input.trigger('change');

    expect(mockAlert).not.toHaveBeenCalled();
    expect(attachmentNames(wrapper)).toEqual(['valido.txt']);
  });

  it('says the pasted file was empty, since a paste of Files alone carries no text', async () => {
    const wrapper = mountEditor();

    await editor(wrapper).trigger('paste', {
      clipboardData: {
        types: ['Files'],
        files: [file('vazio.txt', 'text/plain', 0)],
      },
    });

    expect(mockAlert).toHaveBeenCalledWith('CONVERSATION.FILE_IS_EMPTY');
  });

  // Internal chat has no macOS Numbers argument of its own, but it shares the composer's rule so
  // the two do not drift: a rich copy brings an invalid zero-byte attachment beside its text.
  it('stays quiet for a rich paste that carries text beside its empty attachment', async () => {
    const wrapper = mountEditor();

    await editor(wrapper).trigger('paste', {
      clipboardData: {
        types: ['text/plain', 'text/html', 'text/rtf', 'Files'],
        files: [file('image.png', 'image/png', 0)],
      },
    });

    expect(mockAlert).not.toHaveBeenCalled();
  });

  it('still attaches a real pasted file', async () => {
    const wrapper = mountEditor();

    await editor(wrapper).trigger('paste', {
      clipboardData: {
        types: ['Files'],
        files: [file('valido.txt', 'text/plain', 4)],
      },
    });

    expect(mockAlert).not.toHaveBeenCalled();
    expect(attachmentNames(wrapper)).toEqual(['valido.txt']);
  });

  it('applies the same rule to a drop', async () => {
    const wrapper = mountEditor();

    await editor(wrapper).trigger('drop', {
      dataTransfer: {
        types: ['Files'],
        files: [file('vazio.txt', 'text/plain', 0)],
      },
    });

    expect(mockAlert).toHaveBeenCalledWith('CONVERSATION.FILE_IS_EMPTY');
  });
});
