import { describe, it, expect, beforeEach, vi } from 'vitest';
import { defineComponent } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import ConversationHistorySync from '../ConversationHistorySync.vue';

const mockDispatch = vi.fn();
vi.mock('vuex', () => ({ useStore: () => ({ dispatch: mockDispatch }) }));

vi.mock('vue-i18n', async () => {
  const actual = await vi.importActual('vue-i18n');
  return { ...actual, useI18n: () => ({ t: key => key }) };
});

const mockAlert = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => mockAlert(...args),
}));

const mountControl = () =>
  mount(ConversationHistorySync, {
    props: { conversationId: 7 },
    global: {
      stubs: {
        NextButton: defineComponent({
          name: 'NextButton',
          template:
            '<button class="NextButton-stub" @click="$emit(\'click\')" />',
        }),
      },
    },
  });

const button = wrapper => wrapper.find('.NextButton-stub');

describe('ConversationHistorySync', () => {
  beforeEach(() => vi.clearAllMocks());

  it('asks the provider for the page before this thread', async () => {
    mockDispatch.mockResolvedValue({});
    const wrapper = mountControl();

    await button(wrapper).trigger('click');
    await flushPromises();

    expect(mockDispatch).toHaveBeenCalledWith('syncHistory', 7);
  });

  // The phone answers on the webhook minutes later, or never, so the press can only
  // report that the request went out.
  it('reports that the phone was asked', async () => {
    mockDispatch.mockResolvedValue({});
    const wrapper = mountControl();

    await button(wrapper).trigger('click');
    await flushPromises();

    expect(mockAlert).toHaveBeenCalledWith(
      'CONVERSATION.HISTORY_SYNC.REQUESTED'
    );
  });

  it('reports a request the server refused', async () => {
    mockDispatch.mockRejectedValue(new Error('nope'));
    const wrapper = mountControl();

    await button(wrapper).trigger('click');
    await flushPromises();

    expect(mockAlert).toHaveBeenCalledWith('CONVERSATION.HISTORY_SYNC.ERROR');
  });
});
