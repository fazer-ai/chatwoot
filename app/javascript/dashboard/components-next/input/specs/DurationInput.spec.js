import { defineComponent, ref } from 'vue';
import { mount } from '@vue/test-utils';
import DurationInput from '../DurationInput.vue';

const mountDurationInput = ({ initialValue = null } = {}) => {
  const TestHost = defineComponent({
    components: { DurationInput },
    setup() {
      const duration = ref(initialValue);
      const unit = ref('minutes');
      const submittedDuration = ref(null);

      const handleSubmit = () => {
        submittedDuration.value = duration.value;
      };

      return { duration, unit, submittedDuration, handleSubmit };
    },
    template: `
      <form @submit.prevent="handleSubmit">
        <DurationInput
          v-model="duration"
          v-model:unit="unit"
          :min="10"
          :max="100"
        />
        <output data-testid="duration">{{ duration }}</output>
        <output data-testid="submitted-duration">
          {{ submittedDuration }}
        </output>
      </form>
    `,
  });

  return mount(TestHost);
};

describe('DurationInput', () => {
  it('allows a multi-digit value to be typed before enforcing the minimum', async () => {
    const wrapper = mountDurationInput();
    const input = wrapper.get('input');

    await input.setValue('4');
    expect(input.element.value).toBe('4');

    await input.setValue(`${input.element.value}5`);
    expect(input.element.value).toBe('45');
    expect(wrapper.get('[data-testid="duration"]').text()).toBe('45');
  });

  it('normalizes values to the configured range on blur', async () => {
    const wrapper = mountDurationInput();
    const input = wrapper.get('input');

    await input.setValue('4');
    await input.trigger('blur');
    expect(input.element.value).toBe('10');

    await input.setValue('125');
    await input.trigger('blur');
    expect(input.element.value).toBe('100');
  });

  it('normalizes the value before Enter submits the form', async () => {
    const wrapper = mountDurationInput();
    const input = wrapper.get('input');

    await input.setValue('125');
    await input.trigger('keydown', { key: 'Enter' });
    await wrapper.get('form').trigger('submit');

    expect(wrapper.get('[data-testid="submitted-duration"]').text()).toBe(
      '100'
    );
  });
});

const mountWithUnit = ({
  initialValue = null,
  initialUnit = 'hours',
  min = 10,
  max = 43200,
} = {}) => {
  const TestHost = defineComponent({
    components: { DurationInput },
    setup() {
      const duration = ref(initialValue);
      const unit = ref(initialUnit);
      return { duration, unit, min, max };
    },
    template: `
      <DurationInput v-model="duration" v-model:unit="unit" :min="min" :max="max" />
      <output data-testid="duration">{{ duration }}</output>
    `,
  });

  return mount(TestHost);
};

describe('DurationInput unit change', () => {
  it('keeps the typed number when the user picks another unit', async () => {
    const wrapper = mountWithUnit();
    const input = wrapper.get('input');

    await input.setValue('2');
    await input.trigger('blur');
    await wrapper.get('select').setValue('days');

    expect(input.element.value).toBe('2');
    expect(wrapper.get('[data-testid="duration"]').text()).toBe('2880');
  });

  it('keeps the typed number when the parent does not bind the unit', async () => {
    const TestHost = defineComponent({
      components: { DurationInput },
      setup() {
        return { duration: ref(null) };
      },
      template: `
        <DurationInput v-model="duration" :min="10" :max="43200" />
        <output data-testid="duration">{{ duration }}</output>
      `,
    });
    const wrapper = mount(TestHost);
    const input = wrapper.get('input');

    await input.setValue('120');
    await input.trigger('blur');
    await wrapper.get('select').setValue('hours');

    expect(input.element.value).toBe('120');
    expect(wrapper.get('[data-testid="duration"]').text()).toBe('7200');
  });

  it('keeps the typed number going down a unit too', async () => {
    const wrapper = mountWithUnit({ initialUnit: 'minutes' });
    const input = wrapper.get('input');

    await input.setValue('90');
    await input.trigger('blur');
    await wrapper.get('select').setValue('hours');

    expect(input.element.value).toBe('90');
    expect(wrapper.get('[data-testid="duration"]').text()).toBe('5400');
  });

  it('does not replace a number past the maximum with the bound on a unit change', async () => {
    const wrapper = mountWithUnit();
    const input = wrapper.get('input');

    await input.setValue('48');
    await input.trigger('blur');
    await wrapper.get('select').setValue('days');

    expect(input.element.value).toBe('48');
    expect(wrapper.get('[data-testid="duration"]').text()).toBe('69120');
  });

  it('leaves an empty field empty on a unit change', async () => {
    const wrapper = mountWithUnit();
    const input = wrapper.get('input');

    await input.setValue('');
    await wrapper.get('select').setValue('days');

    expect(input.element.value).toBe('');
    expect(wrapper.get('[data-testid="duration"]').text()).toBe('');
  });

  it('does not carry a picked number into a later unit set by the parent', async () => {
    const wrapper = mountWithUnit();
    const input = wrapper.get('input');

    await input.setValue('2');
    await input.trigger('blur');
    await wrapper.get('select').setValue('days');

    // The form reopens on another rule: 90 minutes, shown in minutes.
    wrapper.vm.duration = 90;
    wrapper.vm.unit = 'minutes';
    await wrapper.vm.$nextTick();
    await wrapper.vm.$nextTick();

    expect(input.element.value).toBe('90');
    expect(wrapper.get('[data-testid="duration"]').text()).toBe('90');
  });

  it('keeps the duration when the parent sets the unit to show a saved value', async () => {
    const wrapper = mountWithUnit({ initialUnit: 'minutes' });

    wrapper.vm.duration = 2880;
    await wrapper.vm.$nextTick();
    wrapper.vm.unit = 'days';
    await wrapper.vm.$nextTick();
    await wrapper.vm.$nextTick();

    expect(wrapper.get('input').element.value).toBe('2');
    expect(wrapper.get('[data-testid="duration"]').text()).toBe('2880');
  });
});
