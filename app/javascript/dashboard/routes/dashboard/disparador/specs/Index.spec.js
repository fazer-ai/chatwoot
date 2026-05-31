import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import Index from '../Index.vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables');
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, named) => (named ? `${key}:${JSON.stringify(named)}` : key),
  }),
}));

const disparo = { id: 5, name: 'June', status: 'draft', inbox_ids: [1] };

const stubs = {
  CampaignLayout: { template: '<div><slot name="action" /><slot /></div>' },
  Spinner: { template: '<div class="stub-spinner" />' },
  EmptyStateLayout: {
    template: '<div class="stub-empty"><slot name="actions" /></div>',
  },
  BaseTable: {
    name: 'BaseTable',
    props: ['items'],
    template: '<table><slot name="row" :items="items" /></table>',
  },
  BaseTableRow: {
    name: 'BaseTableRow',
    props: ['item'],
    template: '<tr><slot /></tr>',
  },
  BaseTableCell: { template: '<td><slot /></td>' },
  CreateDisparo: { template: '<div />', methods: { open() {} } },
  DryRunResult: { template: '<div />', methods: { run() {} } },
  TargetsView: { template: '<div />', methods: { open() {} } },
  Button: {
    name: 'Button',
    props: ['disabled', 'isLoading', 'label', 'icon'],
    template:
      '<button class="stub-button" :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
  },
  RouterLink: { template: '<a><slot /></a>' },
};

describe('Index.vue (Disparador list)', () => {
  let dispatch;
  let snapshotByDisparo;

  const mountComponent = () =>
    mount(Index, {
      global: {
        mocks: { $t: key => key },
        stubs,
      },
    });

  const getterMock = name => {
    if (name === 'disparador/getDisparos') return ref([disparo]);
    if (name === 'disparador/getUIFlags') {
      return ref({ isFetching: false, isShadowRunning: false });
    }
    if (name === 'disparador/getSnapshotId') {
      return ref(id => snapshotByDisparo[id]);
    }
    if (name === 'inboxes/getInboxes') return ref([{ id: 1, name: 'Cloud A' }]);
    return ref([]);
  };

  beforeEach(() => {
    vi.clearAllMocks();
    snapshotByDisparo = {};
    dispatch = vi.fn().mockResolvedValue([]);
    useStore.mockReturnValue({
      dispatch,
      getters: { getCurrentAccountId: 7 },
    });
    useStoreGetters.mockReturnValue(
      new Proxy({}, { get: (_t, prop) => getterMock(prop) })
    );
    useAlert.mockImplementation(() => {});
  });

  // The shadow-run button (2nd action button) is disabled until a dry-run has
  // produced an approved snapshot for that disparo.
  const shadowButton = wrapper => wrapper.findAll('.stub-button')[2];

  it('disables the shadow-run button when no approved snapshot exists', () => {
    const wrapper = mountComponent();
    expect(shadowButton(wrapper).attributes('disabled')).toBeDefined();
  });

  it('enables the shadow-run button once a snapshot is held for the disparo', () => {
    snapshotByDisparo = { 5: 'snap-5' };
    const wrapper = mountComponent();
    expect(shadowButton(wrapper).attributes('disabled')).toBeUndefined();
  });

  it('shadow-run passes the approved snapshot_id to the store action', async () => {
    snapshotByDisparo = { 5: 'snap-5' };
    dispatch.mockResolvedValue({ created: 3, eligible: 3, skipped: 0 });
    const wrapper = mountComponent();

    await shadowButton(wrapper).trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('disparador/shadowRun', {
      id: 5,
      snapshotId: 'snap-5',
    });
  });

  it('surfaces the re-dry-run prompt when shadow-run returns invalid_shadow_run (422)', async () => {
    snapshotByDisparo = { 5: 'snap-5' };
    dispatch.mockImplementation(action => {
      if (action === 'disparador/shadowRun') {
        return Promise.reject(new Error('invalid_shadow_run'));
      }
      return Promise.resolve([]);
    });
    const wrapper = mountComponent();

    await shadowButton(wrapper).trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'DISPARADOR_MGMT.SHADOW_RUN.API.ERRORS.INVALID_SHADOW_RUN'
    );
  });
});
