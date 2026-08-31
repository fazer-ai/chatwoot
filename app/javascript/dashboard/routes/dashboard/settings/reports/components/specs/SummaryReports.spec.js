import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import SummaryReports from '../SummaryReports.vue';

const agents = [
  { id: 1, name: 'Alice' },
  { id: 2, name: 'Bob' },
  { id: 3, name: 'Carol' },
  { id: 4, name: 'Dave' },
];

// Bob replies fastest and takes the fewest; Dave has no activity at all.
const metrics = [
  { id: 1, conversationsCount: 9, avgFirstResponseTime: 600 },
  { id: 2, conversationsCount: 10, avgFirstResponseTime: 120 },
  { id: 3, conversationsCount: 2, avgFirstResponseTime: 3600 },
  { id: 4 },
];

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn(), getters: {} }),
  useMapGetter: key => {
    if (key[0] === 'agents/getAgents') return ref(agents);
    if (key[0] === 'summaryReports/getAgentSummaryReports') return ref(metrics);
    return ref({});
  },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const mountReports = () =>
  mount(SummaryReports, {
    props: {
      type: 'agent',
      getterKey: 'agents/getAgents',
      actionKey: 'summaryReports/fetchAgentSummaryReports',
      fetchItemsKey: 'agents/get',
      summaryKey: 'summaryReports/getAgentSummaryReports',
    },
    global: {
      stubs: {
        OverviewReportFilters: true,
        SummaryDistribution: true,
        SummaryReportLink: {
          props: ['row'],
          template: '<span>{{ row.original.name }}</span>',
        },
        Spinner: true,
      },
      mocks: { $t: key => key },
    },
  });

const columnOf = (wrapper, index) =>
  wrapper.findAll('tbody tr').map(row => row.findAll('td')[index].text());

const sortBy = (wrapper, headerIndex) =>
  wrapper.findAll('th')[headerIndex].trigger('click');

describe('SummaryReports.vue', () => {
  it('sorts a count column by its number, not by the formatted string', async () => {
    const wrapper = mountReports();
    await sortBy(wrapper, 1);

    // 10 above 9 is the whole point: as strings they sort the other way round.
    expect(columnOf(wrapper, 1)).toEqual(['10', '9', '2', '--']);
  });

  it('sorts a duration column by its seconds', async () => {
    const wrapper = mountReports();
    await sortBy(wrapper, 2);

    expect(columnOf(wrapper, 0)).toEqual(['Carol', 'Alice', 'Bob', 'Dave']);
  });

  it('keeps rows with no measurement at the bottom in both directions', async () => {
    const wrapper = mountReports();

    await sortBy(wrapper, 2);
    expect(columnOf(wrapper, 0).at(-1)).toBe('Dave');

    await sortBy(wrapper, 2);
    expect(columnOf(wrapper, 0)).toEqual(['Bob', 'Alice', 'Carol', 'Dave']);
  });
});
