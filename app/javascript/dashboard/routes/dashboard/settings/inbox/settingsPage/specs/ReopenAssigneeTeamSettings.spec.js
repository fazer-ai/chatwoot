import { describe, it, expect, beforeEach, vi } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import ReopenAssigneeTeamSettings from '../ReopenAssigneeTeamSettings.vue';

const TEAMS = [
  { id: 3, name: 'plantao' },
  { id: 8, name: 'vendas' },
];

const mockDispatch = vi.fn();
vi.mock('vuex', () => ({
  useStore: () => ({
    dispatch: mockDispatch,
    getters: { 'teams/getTeams': TEAMS },
  }),
}));

vi.mock('vue-i18n', async () => {
  const actual = await vi.importActual('vue-i18n');
  return { ...actual, useI18n: () => ({ t: key => key }) };
});

const mockAlert = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => mockAlert(...args),
}));

const mountSection = inbox =>
  mount(ReopenAssigneeTeamSettings, {
    props: { inbox },
    global: { mocks: { $t: key => key } },
  });

describe('ReopenAssigneeTeamSettings', () => {
  beforeEach(() => vi.clearAllMocks());

  it('shows the saved team', () => {
    const wrapper = mountSection({ id: 1, reopen_assignee_team_id: 8 });

    expect(wrapper.find('select').element.value).toBe('8');
  });

  // A deleted team is nullified on the server before the cached inbox refetches.
  it('shows None when the saved team is not among the account teams', () => {
    const wrapper = mountSection({ id: 1, reopen_assignee_team_id: 99 });

    expect(wrapper.find('select').element.value).toBe('');
  });

  it('saves the chosen team', async () => {
    const wrapper = mountSection({ id: 1, reopen_assignee_team_id: null });

    await wrapper.find('select').setValue('3');
    await flushPromises();

    expect(mockDispatch).toHaveBeenCalledWith('inboxes/updateInbox', {
      id: 1,
      formData: false,
      reopen_assignee_team_id: 3,
    });
    expect(mockAlert).toHaveBeenCalledWith(
      'INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'
    );
  });

  it('clears the setting with None', async () => {
    const wrapper = mountSection({ id: 1, reopen_assignee_team_id: 3 });

    await wrapper.find('select').setValue('');
    await flushPromises();

    expect(mockDispatch).toHaveBeenCalledWith('inboxes/updateInbox', {
      id: 1,
      formData: false,
      reopen_assignee_team_id: null,
    });
  });

  it('goes back to the saved team when the server refuses the change', async () => {
    mockDispatch.mockRejectedValueOnce(new Error('422'));
    const wrapper = mountSection({ id: 1, reopen_assignee_team_id: 3 });

    await wrapper.find('select').setValue('8');
    await flushPromises();

    expect(wrapper.find('select').element.value).toBe('3');
    expect(mockAlert).toHaveBeenCalledWith('INBOX_MGMT.EDIT.API.ERROR_MESSAGE');
  });
});
