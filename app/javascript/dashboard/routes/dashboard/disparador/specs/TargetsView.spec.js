import { mount, flushPromises } from '@vue/test-utils';
import TargetsView from '../TargetsView.vue';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables');
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, named) => (named ? `${key}:${JSON.stringify(named)}` : key),
  }),
}));

const TARGETS_PER_PAGE = 50;
const makeTargets = count =>
  Array.from({ length: count }, (_, i) => ({
    id: i + 1,
    conversation_id: 100 + i,
    contact_id: 200 + i,
    state: 'queued',
    primary_skip_reason: null,
    phone_present: true,
  }));

const stubs = {
  Dialog: {
    name: 'Dialog',
    template: '<div class="stub-dialog"><slot /></div>',
    methods: { open() {}, close() {} },
  },
  Spinner: { template: '<div class="stub-spinner" />' },
  BaseTable: {
    name: 'BaseTable',
    props: ['items'],
    template: '<table><slot name="row" :items="items" /></table>',
  },
  BaseTableRow: { props: ['item'], template: '<tr><slot /></tr>' },
  BaseTableCell: { template: '<td><slot /></td>' },
  Button: {
    name: 'Button',
    props: ['disabled', 'label', 'icon'],
    template:
      '<button class="stub-button" :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
  },
};

describe('TargetsView.vue', () => {
  let dispatch;

  const mountComponent = () =>
    mount(TargetsView, { global: { mocks: { $t: key => key }, stubs } });

  beforeEach(() => {
    vi.clearAllMocks();
    dispatch = vi.fn();
    useStore.mockReturnValue({ dispatch });
    useAlert.mockImplementation(() => {});
  });

  it('fetches page 1 on open and renders the targets', async () => {
    dispatch.mockResolvedValue(makeTargets(3));
    const wrapper = mountComponent();

    wrapper.vm.open({ id: 5, name: 'June' });
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('disparador/getTargets', {
      id: 5,
      page: 1,
    });
    expect(wrapper.findAll('tr')).toHaveLength(3);
  });

  it('advances to the next page when the page came back full', async () => {
    dispatch.mockResolvedValue(makeTargets(TARGETS_PER_PAGE));
    const wrapper = mountComponent();
    wrapper.vm.open({ id: 5, name: 'June' });
    await flushPromises();

    await wrapper.vm.goToNextPage();
    await flushPromises();

    expect(dispatch).toHaveBeenLastCalledWith('disparador/getTargets', {
      id: 5,
      page: 2,
    });
    expect(wrapper.vm.page).toBe(2);
  });

  it('shows the in-view error + retry when the first-page fetch fails', async () => {
    dispatch.mockRejectedValue(new Error('boom'));
    const wrapper = mountComponent();

    wrapper.vm.open({ id: 5, name: 'June' });
    await flushPromises();

    expect(wrapper.vm.loadError).toBe(true);
    expect(wrapper.html()).toContain('TARGETS.LOAD_ERROR.TITLE');
  });

  it('retry re-fetches the page that failed and clears the error', async () => {
    dispatch.mockRejectedValueOnce(new Error('boom'));
    const wrapper = mountComponent();
    wrapper.vm.open({ id: 5, name: 'June' });
    await flushPromises();
    expect(wrapper.vm.loadError).toBe(true);

    dispatch.mockResolvedValueOnce(makeTargets(2));
    await wrapper.vm.retry();
    await flushPromises();

    expect(wrapper.vm.loadError).toBe(false);
    expect(wrapper.findAll('tr')).toHaveLength(2);
  });

  it('keeps existing rows and toasts when a mid-pagination fetch fails', async () => {
    dispatch.mockResolvedValueOnce(makeTargets(TARGETS_PER_PAGE));
    const wrapper = mountComponent();
    wrapper.vm.open({ id: 5, name: 'June' });
    await flushPromises();

    dispatch.mockRejectedValueOnce(new Error('boom'));
    await wrapper.vm.goToNextPage();
    await flushPromises();

    // Rows from page 1 remain; the error is a transient toast, not the in-view
    // error state (which would falsely read as an empty audience).
    expect(wrapper.vm.loadError).toBe(false);
    expect(useAlert).toHaveBeenCalled();
  });
});
