import { nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import BaseHeatmap from '../BaseHeatmap.vue';

vi.mock('@chatwoot/viz', () => ({
  HeatmapChart: { name: 'HeatmapChart', props: ['data'], template: '<div />' },
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: { DAYS_OF_WEEK: { SUNDAY: 'Sunday' } },
    pt_BR: { DAYS_OF_WEEK: { SUNDAY: 'Domingo' } },
  },
});

describe('BaseHeatmap', () => {
  it('names the days in the language applied after it mounted', async () => {
    const sunday = new Date(2026, 10, 8, 10).getTime() / 1000;
    const wrapper = mount(BaseHeatmap, {
      props: {
        heatmapData: [{ timestamp: sunday, value: 1 }],
        ariaLabel: 'heatmap',
        formatValue: value => value,
      },
      global: { plugins: [i18n] },
    });
    const dayLabel = () =>
      wrapper.findComponent({ name: 'HeatmapChart' }).props('data').rows[0]
        .label;
    expect(dayLabel()).toBe('Sunday');

    i18n.global.locale.value = 'pt_BR';
    await nextTick();
    expect(dayLabel()).toBe('Domingo');
  });
});
