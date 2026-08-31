import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import SummaryDistribution from '../SummaryDistribution.vue';

const push = vi.fn();

vi.mock('vue-router', () => ({
  useRouter: () => ({ push }),
}));

const buildI18n = () =>
  createI18n({
    legacy: false,
    locale: 'en',
    messages: {
      en: {
        REPORT: {
          DISTRIBUTION: {
            TITLE: {
              AGENT: 'Distribution by agent',
              INBOX: 'Distribution by inbox',
            },
            METRIC: { CONVERSATIONS: 'Conversations', RESOLUTIONS: 'Resolved' },
            OTHERS: 'Others ({count})',
            ASSIGNED_ONLY: 'Counts only conversations that have an assignee.',
          },
        },
      },
    },
  });

const buildRows = (count, value) =>
  Array.from({ length: count }, (_, index) => ({
    id: index + 1,
    name: `Agent ${index + 1}`,
    conversationsCount: value ?? count - index,
    resolvedConversationsCount: 1,
  }));

const mountComponent = (props = {}) =>
  mount(SummaryDistribution, {
    props: { type: 'agent', rows: buildRows(3), ...props },
    global: {
      plugins: [buildI18n()],
      stubs: { TabBar: true },
    },
  });

// Name, count and share; the second cell is the bar track and carries no text.
const rowsOf = wrapper =>
  wrapper.findAll('li').map(row => {
    const [name, , count, share] = [...row.element.firstElementChild.children];
    return [name, count, share].map(cell => cell.textContent.trim()).join(' ');
  });

const barWidthsOf = wrapper =>
  wrapper
    .findAll('li span[style]')
    .map(bar => Number.parseFloat(bar.attributes('style').match(/[\d.]+/)[0]));

describe('SummaryDistribution.vue', () => {
  beforeEach(() => push.mockClear());

  it('ranks rows by the active metric and shows each share of the total', () => {
    const wrapper = mountComponent({
      rows: [
        { id: 1, name: 'Alice', conversationsCount: 20 },
        { id: 2, name: 'Bob', conversationsCount: 60 },
        { id: 3, name: 'Carol', conversationsCount: 20 },
      ],
    });

    expect(rowsOf(wrapper)).toEqual([
      'Bob 60 60%',
      'Alice 20 20%',
      'Carol 20 20%',
    ]);
  });

  it('leaves out rows the period has nothing for', () => {
    const wrapper = mountComponent({
      rows: [
        { id: 1, name: 'Alice', conversationsCount: 5 },
        { id: 2, name: 'Bob', conversationsCount: 0 },
        { id: 3, name: 'Carol', conversationsCount: undefined },
        { id: 4, name: 'Dave', conversationsCount: 5 },
      ],
    });

    expect(rowsOf(wrapper)).toEqual(['Alice 5 50%', 'Dave 5 50%']);
  });

  it('aggregates everything past the tenth row into a single tail row', () => {
    const wrapper = mountComponent({ rows: buildRows(13) });
    const rows = rowsOf(wrapper);

    // 13 down to 4 stay named, 3 + 2 + 1 land in the tail.
    expect(rows).toHaveLength(11);
    expect(rows.at(-1)).toBe('Others (3) 6 6.6%');
  });

  it('keeps the tail bar inside the track when it outgrows the biggest row', () => {
    // Twelve rows of ten: the two-row tail is worth twice the biggest one.
    const widths = barWidthsOf(mountComponent({ rows: buildRows(12, 10) }));

    expect(widths.at(-1)).toBe(100);
    expect(Math.max(...widths.slice(0, -1))).toBe(50);
  });

  it('renders nothing until there are two rows to compare', () => {
    const wrapper = mountComponent({
      rows: [{ id: 1, name: 'Alice', conversationsCount: 9 }],
    });

    expect(wrapper.find('h3').exists()).toBe(false);
  });

  it('opens the report of the row that was clicked', async () => {
    const wrapper = mountComponent();
    await wrapper.findAll('li button')[0].trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'agent_reports_show',
      params: { id: 1 },
    });
  });

  it('does not link the aggregated tail anywhere', () => {
    const wrapper = mountComponent({ rows: buildRows(13) });

    expect(wrapper.findAll('li button')).toHaveLength(10);
  });

  it('warns that the total leaves unassigned conversations out, except on inboxes', () => {
    const assignedOnly = 'Counts only conversations that have an assignee.';

    expect(mountComponent().text()).toContain(assignedOnly);
    expect(mountComponent({ type: 'inbox' }).text()).not.toContain(
      assignedOnly
    );
  });
});
