import axios from 'axios';
import actions, {
  hasMessageFailedWithExternalError,
} from '../../conversations/actions';
import types from '../../../mutation-types';
const dataToSend = {
  payload: [
    {
      attribute_key: 'status',
      filter_operator: 'equal_to',
      values: ['open'],
      query_operator: null,
    },
  ],
};
import { dataReceived } from './testConversationResponse';

const commit = vi.fn();
const dispatch = vi.fn();
global.axios = axios;
vi.mock('axios');

describe('#hasMessageFailedWithExternalError', () => {
  it('returns false if message is sent', () => {
    const pendingMessage = {
      status: 'sent',
      content_attributes: {},
    };
    expect(hasMessageFailedWithExternalError(pendingMessage)).toBe(false);
  });
  it('returns false if status is not failed', () => {
    const pendingMessage = {
      status: 'progress',
      content_attributes: {},
    };
    expect(hasMessageFailedWithExternalError(pendingMessage)).toBe(false);
  });

  it('returns false if status is failed but no external error', () => {
    const pendingMessage = {
      status: 'failed',
      content_attributes: {},
    };
    expect(hasMessageFailedWithExternalError(pendingMessage)).toBe(false);
  });

  it('returns true if status is failed and has external error', () => {
    const pendingMessage = {
      status: 'failed',
      content_attributes: {
        external_error: 'error',
      },
    };
    expect(hasMessageFailedWithExternalError(pendingMessage)).toBe(true);
  });
});

describe('#actions', () => {
  describe('#getConversation', () => {
    it('sends correct actions if API is success', async () => {
      axios.get.mockResolvedValue({
        data: { id: 1, meta: { sender: { id: 1, name: 'Contact 1' } } },
      });
      await actions.getConversation({ commit }, 1);
      expect(commit.mock.calls).toEqual([
        [
          types.UPDATE_CONVERSATION,
          { id: 1, meta: { sender: { id: 1, name: 'Contact 1' } } },
        ],
        ['contacts/SET_CONTACT_ITEM', { id: 1, name: 'Contact 1' }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.get.mockRejectedValue({ message: 'Incorrect header' });
      await actions.getConversation({ commit });
      expect(commit.mock.calls).toEqual([]);
    });
  });
  describe('#muteConversation', () => {
    it('sends correct actions if API is success', async () => {
      axios.get.mockResolvedValue(null);
      await actions.muteConversation({ commit }, 1);
      expect(commit.mock.calls).toEqual([[types.MUTE_CONVERSATION]]);
    });
    it('sends correct actions if API is error', async () => {
      axios.get.mockRejectedValue({ message: 'Incorrect header' });
      await actions.getConversation({ commit });
      expect(commit.mock.calls).toEqual([]);
    });
  });

  describe('#updateConversation', () => {
    it('sends setContact action and update_conversation mutation', () => {
      const conversation = {
        id: 1,
        messages: [],
        meta: { sender: { id: 1, name: 'john-doe' } },
        labels: ['support'],
      };
      actions.updateConversation(
        { commit, rootState: { route: { name: 'home' } }, dispatch },
        conversation
      );
      expect(commit.mock.calls).toEqual([
        [types.UPDATE_CONVERSATION, conversation],
      ]);
      expect(dispatch.mock.calls).toEqual([
        [
          'conversationLabels/setConversationLabel',
          { id: 1, data: ['support'] },
        ],
        [
          'contacts/setContact',
          {
            id: 1,
            name: 'john-doe',
          },
        ],
      ]);
    });
  });

  describe('#addConversation', () => {
    it('doesnot send mutation if conversation is from a different inbox', () => {
      const conversation = {
        id: 1,
        messages: [],
        meta: { sender: { id: 1, name: 'john-doe' } },
        inbox_id: 2,
      };
      actions.addConversation(
        {
          commit,
          rootState: { route: { name: 'home' } },
          dispatch,
          state: { currentInbox: 1, appliedFilters: [] },
        },
        conversation
      );
      expect(commit.mock.calls).toEqual([]);
      expect(dispatch.mock.calls).toEqual([]);
    });

    it('doesnot send mutation if conversation filters are applied', () => {
      const conversation = {
        id: 1,
        messages: [],
        meta: { sender: { id: 1, name: 'john-doe' } },
        inbox_id: 1,
      };
      actions.addConversation(
        {
          commit,
          rootState: { route: { name: 'home' } },
          dispatch,
          state: { currentInbox: 1, appliedFilters: [{ id: 'random-filter' }] },
        },
        conversation
      );
      expect(commit.mock.calls).toEqual([]);
      expect(dispatch.mock.calls).toEqual([]);
    });

    it('doesnot send mutation if the view is conversation mentions', () => {
      const conversation = {
        id: 1,
        messages: [],
        meta: { sender: { id: 1, name: 'john-doe' } },
        inbox_id: 1,
      };
      actions.addConversation(
        {
          commit,
          rootState: { route: { name: 'conversation_mentions' } },
          dispatch,
          state: { currentInbox: 1, appliedFilters: [{ id: 'random-filter' }] },
        },
        conversation
      );
      expect(commit.mock.calls).toEqual([]);
      expect(dispatch.mock.calls).toEqual([]);
    });

    it('doesnot send mutation if the view is conversation folders', () => {
      const conversation = {
        id: 1,
        messages: [],
        meta: { sender: { id: 1, name: 'john-doe' } },
        inbox_id: 1,
      };
      actions.addConversation(
        {
          commit,
          rootState: { route: { name: 'folder_conversations' } },
          dispatch,
          state: { currentInbox: 1, appliedFilters: [{ id: 'random-filter' }] },
        },
        conversation
      );
      expect(commit.mock.calls).toEqual([]);
      expect(dispatch.mock.calls).toEqual([]);
    });

    it('sends correct mutations', () => {
      const conversation = {
        id: 1,
        messages: [],
        meta: { sender: { id: 1, name: 'john-doe' } },
        inbox_id: 1,
      };
      actions.addConversation(
        {
          commit,
          rootState: { route: { name: 'home' } },
          dispatch,
          state: { currentInbox: 1, appliedFilters: [] },
        },
        conversation
      );
      expect(commit.mock.calls).toEqual([
        [types.ADD_CONVERSATION, conversation],
      ]);
      expect(dispatch.mock.calls).toEqual([
        [
          'contacts/setContact',
          {
            id: 1,
            name: 'john-doe',
          },
        ],
      ]);
    });

    it('sends correct mutations if inbox filter is not available', () => {
      const conversation = {
        id: 1,
        messages: [],
        meta: { sender: { id: 1, name: 'john-doe' } },
        inbox_id: 1,
      };
      actions.addConversation(
        {
          commit,
          rootState: { route: { name: 'home' } },
          dispatch,
          state: { appliedFilters: [] },
        },
        conversation
      );
      expect(commit.mock.calls).toEqual([
        [types.ADD_CONVERSATION, conversation],
      ]);
      expect(dispatch.mock.calls).toEqual([
        [
          'contacts/setContact',
          {
            id: 1,
            name: 'john-doe',
          },
        ],
      ]);
    });
  });

  describe('#addMessage', () => {
    it('sends correct mutations if message is incoming', () => {
      const message = {
        id: 1,
        message_type: 0,
        conversation_id: 1,
      };
      actions.addMessage({ commit }, message);
      expect(commit.mock.calls).toEqual([
        [types.ADD_MESSAGE, message],
        [
          types.SET_CONVERSATION_CAN_REPLY,
          { conversationId: 1, canReply: true },
        ],
        [types.ADD_CONVERSATION_ATTACHMENTS, message],
      ]);
    });
    it('sends correct mutations if message is not an incoming message', () => {
      const message = {
        id: 1,
        message_type: 1,
        conversation_id: 1,
      };
      actions.addMessage({ commit }, message);
      expect(commit.mock.calls).toEqual([[types.ADD_MESSAGE, message]]);
    });
  });

  describe('#markMessagesRead', () => {
    beforeEach(() => {
      vi.useFakeTimers();
    });

    it('sends correct mutations if api is successful', async () => {
      const lastSeen = new Date().getTime() / 1000;
      axios.post.mockResolvedValue({
        data: { id: 1, agent_last_seen_at: lastSeen },
      });
      await actions.markMessagesRead({ commit }, { id: 1 });
      vi.runAllTimers();
      expect(commit).toHaveBeenCalledTimes(1);
      expect(commit.mock.calls).toEqual([
        [types.UPDATE_MESSAGE_UNREAD_COUNT, { id: 1, lastSeen }],
      ]);
    });
    it('sends correct mutations if api is unsuccessful', async () => {
      axios.post.mockRejectedValue({ message: 'Incorrect header' });
      await actions.markMessagesRead({ commit }, { id: 1 });
      expect(commit.mock.calls).toEqual([]);
    });
  });

  describe('#markMessagesUnread', () => {
    it('sends correct mutations if API is successful', async () => {
      const lastSeen = new Date().getTime() / 1000;
      axios.post.mockResolvedValue({
        data: { id: 1, agent_last_seen_at: lastSeen, unread_count: 1 },
      });
      await actions.markMessagesUnread({ commit }, { id: 1 });
      vi.runAllTimers();
      expect(commit).toHaveBeenCalledTimes(1);
      expect(commit.mock.calls).toEqual([
        [
          types.UPDATE_MESSAGE_UNREAD_COUNT,
          { id: 1, lastSeen, unreadCount: 1 },
        ],
      ]);
    });
    it('sends correct mutations if API is unsuccessful', async () => {
      axios.post.mockRejectedValue({ message: 'Incorrect header' });
      await expect(
        actions.markMessagesUnread({ commit }, { id: 1 })
      ).rejects.toThrow(Error);
    });
  });

  describe('#sendEmailTranscript', () => {
    it('sends correct mutations if api is successful', async () => {
      axios.post.mockResolvedValue({});
      await actions.sendEmailTranscript(
        { commit },
        { conversationId: 1, email: 'testemail@example.com' }
      );
      expect(commit).toHaveBeenCalledTimes(0);
      expect(commit.mock.calls).toEqual([]);
    });
  });

  describe('#assignAgent', () => {
    const owner = { id: 2, name: 'Owner' };
    const getters = {
      getConversationById: () => ({
        meta: { assignee: owner, assignee_type: 'User' },
      }),
    };

    it('commits the optimistic assignee and then the server response', async () => {
      axios.post.mockResolvedValue({
        data: { id: 1, name: 'User' },
      });
      await actions.assignAgent(
        { commit, getters },
        {
          conversationId: 1,
          assignee: { id: 1, name: 'User' },
          assigneeType: 'AgentBot',
        }
      );
      expect(commit.mock.calls).toEqual([
        [
          'ASSIGN_AGENT',
          {
            conversationId: 1,
            assignee: { id: 1, name: 'User' },
            assigneeType: 'AgentBot',
          },
        ],
        [
          'ASSIGN_AGENT',
          {
            conversationId: 1,
            assignee: { id: 1, name: 'User' },
            assigneeType: 'AgentBot',
          },
        ],
      ]);
    });

    // Without the rollback the agent keeps seeing their own name in the
    // assignee field and believes they own a conversation they were denied.
    it('rolls back to the previous assignee and rethrows when rejected', async () => {
      const error = {
        response: { status: 409, data: { agent_name: 'Owner' } },
      };
      axios.post.mockRejectedValue(error);

      await expect(
        actions.assignAgent(
          { commit, dispatch, getters },
          {
            conversationId: 1,
            assignee: { id: 1, name: 'User' },
            assigneeType: 'User',
          }
        )
      ).rejects.toEqual(error);

      expect(commit.mock.calls[1]).toEqual([
        'ASSIGN_AGENT',
        { conversationId: 1, assignee: owner, assigneeType: 'User' },
      ]);
    });

    // The rolled-back snapshot is the thing that went stale during a
    // concurrent claim, so the conflict has to be reconciled with the server.
    it('re-reads the conversation when the assignment was refused', async () => {
      dispatch.mockClear();
      axios.post.mockRejectedValue({
        response: { status: 409, data: { agent_name: 'Owner' } },
      });

      await expect(
        actions.assignAgent(
          { commit, dispatch, getters },
          { conversationId: 1, assignee: { id: 1, name: 'User' } }
        )
      ).rejects.toBeTruthy();

      expect(dispatch).toHaveBeenCalledWith('getConversation', 1);
    });

    it('does not re-read the conversation on an unrelated failure', async () => {
      dispatch.mockClear();
      axios.post.mockRejectedValue({ response: { status: 500 } });

      await expect(
        actions.assignAgent(
          { commit, dispatch, getters },
          { conversationId: 1, assignee: { id: 1, name: 'User' } }
        )
      ).rejects.toBeTruthy();

      expect(dispatch).not.toHaveBeenCalledWith('getConversation', 1);
    });
  });

  describe('#toggleStatus', () => {
    it('sends correct mutations if toggle status is successful', async () => {
      axios.post.mockResolvedValue({
        data: {
          payload: {
            conversation_id: 1,
            current_status: 'snoozed',
            snoozed_until: null,
          },
        },
      });
      await actions.toggleStatus(
        { commit },
        { conversationId: 1, status: 'snoozed' }
      );
      expect(commit).toHaveBeenCalledTimes(1);
      expect(commit.mock.calls).toEqual([
        [
          'CHANGE_CONVERSATION_STATUS',
          { conversationId: 1, status: 'snoozed', snoozedUntil: null },
        ],
      ]);
    });

    // Reopening self-assigns the agent, so a protected inbox refuses the whole
    // request. Swallowing that left every caller announcing a status change
    // that never happened.
    it('rethrows and reconciles when the status change is refused', async () => {
      const error = {
        response: { status: 409, data: { agent_name: 'Owner' } },
      };
      axios.post.mockRejectedValue(error);
      dispatch.mockClear();

      await expect(
        actions.toggleStatus(
          { commit, dispatch },
          { conversationId: 1, status: 'open' }
        )
      ).rejects.toEqual(error);

      expect(dispatch).toHaveBeenCalledWith('getConversation', 1);
    });
  });

  describe('#assignTeam', () => {
    const previousTeam = { id: 9, name: 'Previous' };
    const team = { id: 1, name: 'Team' };
    const getters = {
      getConversationById: () => ({ meta: { team: previousTeam } }),
    };

    it('commits the optimistic team and then the server response', async () => {
      axios.post.mockResolvedValue({ data: team });

      await actions.assignTeam(
        { commit, dispatch, getters },
        { conversationId: 1, team }
      );

      expect(commit.mock.calls).toEqual([
        ['ASSIGN_TEAM', { team, conversationId: 1 }],
        ['ASSIGN_TEAM', { team, conversationId: 1 }],
      ]);
    });

    // Picking a team that excludes the current assignee moves the assignee too,
    // so a protected inbox refuses the whole thing.
    it('rolls back and reconciles when the team change is refused', async () => {
      const error = {
        response: { status: 409, data: { agent_name: 'Owner' } },
      };
      axios.post.mockRejectedValue(error);
      dispatch.mockClear();

      await expect(
        actions.assignTeam(
          { commit, dispatch, getters },
          { conversationId: 1, team }
        )
      ).rejects.toEqual(error);

      expect(commit.mock.calls[1]).toEqual([
        'ASSIGN_TEAM',
        { team: previousTeam, conversationId: 1 },
      ]);
      expect(dispatch).toHaveBeenCalledWith('getConversation', 1);
    });
  });

  describe('#fetchFilteredConversations', () => {
    it('fetches filtered conversations with a mock commit', async () => {
      axios.post.mockResolvedValue({
        data: dataReceived,
      });
      await actions.fetchFilteredConversations(
        { commit, dispatch },
        dataToSend
      );
      expect(commit).toHaveBeenCalledTimes(4);
      expect(commit.mock.calls).toEqual([
        ['SET_LIST_LOADING_STATUS'],
        ['SET_ALL_CONVERSATION', dataReceived.payload],
        ['CLEAR_LIST_LOADING_STATUS'],
        [
          `contacts/${types.SET_CONTACTS}`,
          dataReceived.payload.map(chat => chat.meta.sender),
        ],
      ]);
    });

    it('clears the loading state and rethrows if the request fails', async () => {
      axios.post.mockRejectedValue(new Error('Request failed'));
      await expect(
        actions.fetchFilteredConversations({ commit }, dataToSend)
      ).rejects.toThrow('Request failed');
      expect(commit.mock.calls).toEqual([
        ['SET_LIST_LOADING_STATUS'],
        ['CLEAR_LIST_LOADING_STATUS'],
      ]);
    });
  });

  describe('#setConversationFilter', () => {
    it('commits the correct mutation and sets filter state', () => {
      const filters = [
        {
          attribute_key: 'status',
          filter_operator: 'equal_to',
          values: [{ id: 'snoozed', name: 'Snoozed' }],
          query_operator: 'and',
        },
      ];
      actions.setConversationFilters({ commit }, filters);
      expect(commit.mock.calls).toEqual([
        [types.SET_CONVERSATION_FILTERS, filters],
      ]);
    });
  });

  describe('#clearConversationFilter', () => {
    it('commits the correct mutation and clears filter state', () => {
      actions.clearConversationFilters({ commit });
      expect(commit.mock.calls).toEqual([[types.CLEAR_CONVERSATION_FILTERS]]);
    });
  });

  describe('#updateConversationLastActivity', () => {
    it('sends correct action', async () => {
      await actions.updateConversationLastActivity(
        { commit },
        { conversationId: 1, lastActivityAt: 12121212 }
      );
      expect(commit.mock.calls).toEqual([
        [
          'UPDATE_CONVERSATION_LAST_ACTIVITY',
          { conversationId: 1, lastActivityAt: 12121212 },
        ],
      ]);
    });
  });

  describe('#setChatSortFilter', () => {
    it('sends correct action', async () => {
      await actions.setChatSortFilter(
        { commit },
        { data: 'sort_on_created_at' }
      );
      expect(commit.mock.calls).toEqual([
        ['CHANGE_CHAT_SORT_FILTER', { data: 'sort_on_created_at' }],
      ]);
    });
  });
});

describe('#deleteMessage', () => {
  it('sends correct actions if API is success', async () => {
    const [conversationId, messageId] = [1, 1];
    axios.delete.mockResolvedValue({
      data: { id: 1, content: 'deleted' },
    });
    await actions.deleteMessage({ commit }, { conversationId, messageId });
    expect(commit.mock.calls).toEqual([
      [types.ADD_MESSAGE, { id: 1, content: 'deleted' }],
      [types.DELETE_CONVERSATION_ATTACHMENTS, { id: 1, content: 'deleted' }],
    ]);
  });
  it('sends no actions if API is error', async () => {
    const [conversationId, messageId] = [1, 1];
    axios.delete.mockRejectedValue({ message: 'Incorrect header' });
    await expect(
      actions.deleteMessage({ commit }, { conversationId, messageId })
    ).rejects.toThrow(Error);
    expect(commit.mock.calls).toEqual([]);
  });

  describe('#reconcileConversationTab', () => {
    const filters = { assigneeType: 'unassigned', status: 'open' };
    const onScreen = [
      { id: 1, inbox_id: 7 },
      { id: 2, inbox_id: 7 },
      { id: 3, inbox_id: 8 },
    ];
    const fresh = (id, updatedAt = 200) => ({
      id,
      updated_at: updatedAt,
      meta: { assignee: { id: 42 } },
    });
    const inStore = { 1: { id: 1, updated_at: 100 } };

    const contextWith = (payload, chats = onScreen, stored = inStore) => {
      axios.post.mockResolvedValue({ data: { payload } });
      return {
        commit,
        getters: {
          getUnAssignedChats: () => chats,
          getConversationById: id => stored[id],
        },
      };
    };

    beforeEach(() => {
      commit.mockClear();
      dispatch.mockClear();
      axios.post.mockReset();
    });

    // Evicting would take the conversation out of "all" and out of its new owner's "mine" too,
    // since every tab reads the same cache.
    it('refreshes the stale rows instead of evicting them', async () => {
      const payload = [fresh(1), fresh(2), fresh(3)];
      const removed = await actions.reconcileConversationTab(
        contextWith(payload),
        filters
      );

      expect(commit.mock.calls).toEqual([
        [types.SET_ALL_CONVERSATION, payload],
      ]);
      expect(removed).toEqual([]);
    });

    it('removes only what the server did not return at all', async () => {
      const payload = [fresh(2)];
      const removed = await actions.reconcileConversationTab(
        contextWith(payload),
        filters
      );

      expect(commit.mock.calls).toEqual([
        [types.SET_ALL_CONVERSATION, payload],
        [types.REMOVE_CONVERSATIONS, [1, 3]],
      ]);
      expect(removed).toEqual([
        { id: 1, inboxId: 7 },
        { id: 3, inboxId: 8 },
      ]);
    });

    // The endpoint serializes full conversations and refuses an oversized batch, so a caller that
    // scrolled through several pages has to split the question rather than have it rejected.
    it('splits a list longer than one page into page-sized requests', async () => {
      const many = Array.from({ length: 60 }, (_, i) => ({
        id: i + 1,
        inbox_id: 7,
      }));
      axios.post.mockResolvedValue({ data: { payload: [] } });

      await actions.reconcileConversationTab(
        {
          commit,
          getters: {
            getUnAssignedChats: () => many,
            getConversationById: () => undefined,
          },
        },
        filters
      );

      expect(axios.post).toHaveBeenCalledTimes(3);
      expect(axios.post.mock.calls.map(call => call[1].ids.length)).toEqual([
        25, 25, 10,
      ]);
    });

    it('asks only about the conversations on screen', async () => {
      await actions.reconcileConversationTab(
        contextWith([fresh(1), fresh(2), fresh(3)]),
        filters
      );

      expect(axios.post).toHaveBeenCalledWith(
        expect.stringContaining('/conversations/sync'),
        { ids: [1, 2, 3] }
      );
    });

    // The answer is about the list as it was when the request went out. A conversation that
    // arrives over the cable mid-flight is missing from that answer because it was never asked
    // about, and removing it would undo a live event.
    it('leaves alone a conversation that arrived while the request was in flight', async () => {
      const chats = [...onScreen];
      axios.post.mockImplementation(() => {
        chats.push({ id: 99, inbox_id: 7 });
        return Promise.resolve({
          data: { payload: [fresh(1), fresh(2), fresh(3)] },
        });
      });

      const removed = await actions.reconcileConversationTab(
        {
          commit,
          getters: {
            getUnAssignedChats: () => chats,
            getConversationById: () => undefined,
          },
        },
        filters
      );

      expect(removed).toEqual([]);
      expect(commit.mock.calls).toEqual([
        [types.SET_ALL_CONVERSATION, [fresh(1), fresh(2), fresh(3)]],
      ]);
    });

    // A cable event can beat the response home. Writing the older row back would regress the status
    // or the assignee, and hide the conversation with nothing watching to bring it back.
    it('drops a row the store already holds a newer copy of', async () => {
      const payload = [fresh(1, 50), fresh(2, 300), fresh(3, 300)];
      await actions.reconcileConversationTab(contextWith(payload), filters);

      expect(commit.mock.calls).toEqual([
        [types.SET_ALL_CONVERSATION, [fresh(2, 300), fresh(3, 300)]],
      ]);
    });

    it('keeps a row the store holds an older copy of', async () => {
      const payload = [fresh(1, 500)];
      await actions.reconcileConversationTab(contextWith(payload), filters);

      expect(commit.mock.calls).toEqual([
        [types.SET_ALL_CONVERSATION, [fresh(1, 500)]],
        [types.REMOVE_CONVERSATIONS, [2, 3]],
      ]);
    });

    it('does not call out when the tab is empty on screen', async () => {
      const removed = await actions.reconcileConversationTab(
        contextWith([], []),
        filters
      );

      expect(axios.post).not.toHaveBeenCalled();
      expect(removed).toEqual([]);
    });

    // Mentions and participating carry an assigneeType but are narrowed by a membership the store
    // cannot reproduce, so what is on screen there is not the tab this would judge it against.
    it('does nothing on a view the store cannot reproduce', async () => {
      const removed = await actions.reconcileConversationTab(contextWith([]), {
        ...filters,
        conversationType: 'mention',
      });

      expect(axios.post).not.toHaveBeenCalled();
      expect(removed).toEqual([]);
    });

    it('does nothing on a view that has no tab getter', async () => {
      const removed = await actions.reconcileConversationTab(contextWith([]), {
        assigneeType: 'appliedFilters',
      });

      expect(axios.post).not.toHaveBeenCalled();
      expect(commit.mock.calls).toEqual([]);
      expect(removed).toEqual([]);
    });

    it('keeps the list as is when the request fails', async () => {
      axios.post.mockRejectedValue({ message: 'Network error' });
      const removed = await actions.reconcileConversationTab(
        {
          commit,
          getters: {
            getUnAssignedChats: () => onScreen,
            getConversationById: () => undefined,
          },
        },
        filters
      );

      expect(commit.mock.calls).toEqual([]);
      expect(removed).toEqual([]);
    });
  });

  describe('#deleteConversation', () => {
    it('send correct actions if API is success', async () => {
      axios.delete.mockResolvedValue({
        data: { id: 1 },
      });
      await actions.deleteConversation({ commit, dispatch }, 1);
      expect(commit.mock.calls).toEqual([[types.DELETE_CONVERSATION, 1]]);
      expect(dispatch.mock.calls).toEqual([
        ['conversationStats/get', {}, { root: true }],
      ]);
    });

    it('send no actions if API is error', async () => {
      axios.delete.mockRejectedValue({ message: 'Incorrect header' });
      await expect(
        actions.deleteConversation({ commit, dispatch }, 1)
      ).rejects.toThrow(Error);
      expect(commit.mock.calls).toEqual([]);
      expect(dispatch.mock.calls).toEqual([]);
    });
  });

  describe('#updateCustomAttributes', () => {
    it('update conversation custom attributes', async () => {
      axios.post.mockResolvedValue({
        data: { custom_attributes: { order_d: '1001' } },
      });
      await actions.updateCustomAttributes(
        { commit },
        {
          conversationId: 1,
          customAttributes: { order_d: '1001' },
        }
      );
      expect(commit.mock.calls).toEqual([
        [
          types.UPDATE_CONVERSATION_CUSTOM_ATTRIBUTES,
          {
            conversationId: 1,
            customAttributes: { order_d: '1001' },
          },
        ],
      ]);
    });
  });
});

describe('#addMentions', () => {
  it('does not send mutations if the view is not mentions', () => {
    actions.addMentions(
      { commit, dispatch, rootState: { route: { name: 'home' } } },
      { id: 1 }
    );
    expect(commit.mock.calls).toEqual([]);
    expect(dispatch.mock.calls).toEqual([]);
  });

  it('send mutations if the view is mentions', () => {
    actions.addMentions(
      {
        dispatch,
        rootState: { route: { name: 'conversation_mentions' } },
      },
      { id: 1, meta: { sender: { id: 1 } } }
    );
    expect(dispatch.mock.calls).toEqual([
      ['updateConversation', { id: 1, meta: { sender: { id: 1 } } }],
    ]);
  });

  it('#syncActiveConversationMessages', async () => {
    const conversations = [
      {
        id: 1,
        messages: [
          {
            id: 1,
            content: 'Hello',
          },
        ],
        meta: { sender: { id: 1, name: 'john-doe' } },
        inbox_id: 1,
      },
    ];
    axios.get.mockResolvedValue({
      data: {
        payload: [{ id: 2, content: 'Welcome' }],
        meta: {
          agent_last_seen_at: '2023-04-20T05:22:42.990Z',
        },
      },
    });
    await actions.syncActiveConversationMessages(
      {
        commit,
        dispatch,
        state: {
          allConversations: conversations,
          syncConversationsMessages: {
            1: 1,
          },
        },
      },
      { conversationId: 1 }
    );
    expect(commit.mock.calls).toEqual([
      [
        'conversationMetadata/SET_CONVERSATION_METADATA',
        {
          id: 1,
          data: {
            agent_last_seen_at: '2023-04-20T05:22:42.990Z',
          },
        },
      ],
      [
        'SET_MISSING_MESSAGES',
        {
          id: 1,
          data: [
            { id: 1, content: 'Hello' },
            { id: 2, content: 'Welcome' },
          ],
        },
      ],
      [
        'SET_LAST_MESSAGE_ID_FOR_SYNC_CONVERSATION',
        { conversationId: 1, messageId: null },
      ],
    ]);
  });

  describe('#fetchAllAttachments', () => {
    it('fetches all attachments', async () => {
      axios.get.mockResolvedValue({
        data: {
          payload: [
            {
              id: 1,
              message_id: 1,
              file_type: 'image',
              data_url: '',
              thumb_url: '',
            },
          ],
        },
      });
      await actions.fetchAllAttachments({ commit }, 1);
      expect(commit.mock.calls).toEqual([
        [
          types.SET_ALL_ATTACHMENTS,
          {
            id: 1,
            data: [
              {
                id: 1,
                message_id: 1,
                file_type: 'image',
                data_url: '',
                thumb_url: '',
              },
            ],
          },
        ],
      ]);
    });
  });

  describe('#setContextMenuChatId', () => {
    it('sets the context menu chat id', () => {
      actions.setContextMenuChatId({ commit }, 1);
      expect(commit.mock.calls).toEqual([[types.SET_CONTEXT_MENU_CHAT_ID, 1]]);
    });
  });

  describe('#setChatListFilters', () => {
    it('set chat list filters', () => {
      const filters = {
        inboxId: 1,
        assigneeType: 'me',
        status: 'open',
        sortBy: 'created_at',
        page: 1,
        labels: ['label'],
        teamId: 1,
        conversationType: 'mention',
      };
      actions.setChatListFilters({ commit }, filters);
      expect(commit.mock.calls).toEqual([
        [types.SET_CHAT_LIST_FILTERS, filters],
      ]);
    });
  });

  describe('#updateChatListFilters', () => {
    it('update chat list filters', () => {
      actions.updateChatListFilters({ commit }, { updatedWithin: 20 });
      expect(commit.mock.calls).toEqual([
        [types.UPDATE_CHAT_LIST_FILTERS, { updatedWithin: 20 }],
      ]);
    });
  });

  describe('#setActiveChat', () => {
    it('should commit SET_CHAT_DATA_FETCHED with conversation ID after fetch', async () => {
      const localCommit = vi.fn();
      const localDispatch = vi.fn().mockResolvedValue();
      const data = { id: 42, messages: [{ id: 100 }] };

      await actions.setActiveChat(
        { commit: localCommit, dispatch: localDispatch },
        { data, after: 99 }
      );

      expect(localCommit.mock.calls).toEqual([
        [types.SET_CURRENT_CHAT_WINDOW, data],
        [types.CLEAR_ALL_MESSAGES_LOADED, 42],
        [types.SET_CHAT_DATA_FETCHED, 42],
      ]);
      expect(localDispatch).toHaveBeenCalledWith('fetchPreviousMessages', {
        after: 99,
        before: 100,
        conversationId: 42,
      });
    });

    it('should not dispatch fetchPreviousMessages if dataFetched is already set', async () => {
      const localCommit = vi.fn();
      const localDispatch = vi.fn();
      const data = { id: 42, messages: [{ id: 100 }], dataFetched: true };

      await actions.setActiveChat(
        { commit: localCommit, dispatch: localDispatch },
        { data }
      );

      expect(localCommit.mock.calls).toEqual([
        [types.SET_CURRENT_CHAT_WINDOW, data],
        [types.CLEAR_ALL_MESSAGES_LOADED, 42],
      ]);
      expect(localDispatch).not.toHaveBeenCalled();
    });

    it('should fetch without a cursor when the conversation has no messages', async () => {
      const localCommit = vi.fn();
      const localDispatch = vi.fn().mockResolvedValue();
      const data = { id: 42, messages: [] };

      await actions.setActiveChat(
        { commit: localCommit, dispatch: localDispatch },
        { data }
      );

      expect(localDispatch).toHaveBeenCalledWith('fetchPreviousMessages', {
        after: undefined,
        before: undefined,
        conversationId: 42,
      });
      expect(localCommit).toHaveBeenCalledWith(types.SET_CHAT_DATA_FETCHED, 42);
    });

    it('should commit SET_CHAT_DATA_FETCHED by ID, not mutate the data object directly (race condition fix)', async () => {
      const localCommit = vi.fn();
      const localDispatch = vi.fn().mockResolvedValue();
      const data = { id: 42, messages: [{ id: 100 }] };

      await actions.setActiveChat(
        { commit: localCommit, dispatch: localDispatch },
        { data }
      );

      // The action must NOT set dataFetched on the data object directly
      expect(data.dataFetched).toBeUndefined();

      // Instead it commits a mutation that finds the conversation by ID in the store
      expect(localCommit).toHaveBeenCalledWith(types.SET_CHAT_DATA_FETCHED, 42);
    });
  });

  describe('#getInboxCaptainAssistantById', () => {
    it('fetches inbox assistant by id', async () => {
      axios.get.mockResolvedValue({
        data: {
          id: 1,
          name: 'Assistant',
          description: 'Assistant description',
        },
      });
      await actions.getInboxCaptainAssistantById({ commit }, 1);
      expect(commit.mock.calls).toEqual([
        [
          types.SET_INBOX_CAPTAIN_ASSISTANT,
          { id: 1, name: 'Assistant', description: 'Assistant description' },
        ],
      ]);
    });
  });
});
