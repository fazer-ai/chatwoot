import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import CreateDisparo from '../CreateDisparo.vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables');
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 7 } }),
}));

// Two WhatsApp Cloud inboxes + one non-cloud inbox (must be filtered out of the
// multi-select). The getter is mocked separately to drive the intersection.
const cloudInbox1 = {
  id: 1,
  name: 'Cloud A',
  channel_type: 'Channel::Whatsapp',
  provider: 'whatsapp_cloud',
};
const cloudInbox2 = {
  id: 2,
  name: 'Cloud B',
  channel_type: 'Channel::Whatsapp',
  provider: 'whatsapp_cloud',
};
const onPremInbox = {
  id: 3,
  name: 'On-prem',
  channel_type: 'Channel::Whatsapp',
  provider: 'default',
};

const Dialog = {
  name: 'Dialog',
  props: ['disableConfirmButton'],
  emits: ['confirm'],
  template:
    '<div class="stub-dialog"><slot /><button class="confirm-btn" :disabled="disableConfirmButton" @click="$emit(\'confirm\')" /></div>',
  methods: {
    open() {},
    close() {},
  },
};

const Select = {
  name: 'Select',
  props: ['modelValue', 'options'],
  emits: ['update:modelValue'],
  template:
    '<select class="stub-select" :value="modelValue" @change="$emit(\'update:modelValue\', $event.target.value)"><option v-for="o in options" :key="o.value" :value="o.value">{{ o.label }}</option></select>',
};

const Checkbox = {
  name: 'Checkbox',
  props: ['modelValue'],
  emits: ['change'],
  template:
    '<input type="checkbox" class="stub-checkbox" :checked="modelValue" @change="$emit(\'change\')" />',
};

const mountComponent = () =>
  mount(CreateDisparo, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        Dialog,
        Select,
        Checkbox,
        Input: { name: 'Input', template: '<div class="stub-input" />' },
        TagInput: {
          name: 'TagInput',
          props: ['modelValue'],
          template: '<div class="stub-taginput" />',
        },
        RouterLink: { template: '<a><slot /></a>' },
      },
    },
  });

describe('CreateDisparo.vue', () => {
  let dispatch;
  let templatesByInboxIds;

  const getterMock = name => {
    if (name === 'inboxes/getInboxes') {
      return ref([cloudInbox1, cloudInbox2, onPremInbox]);
    }
    if (name === 'inboxes/getDisparadorWhatsAppTemplates') {
      return ref(ids => templatesByInboxIds(ids));
    }
    if (name === 'labels/getLabels') return ref([]);
    if (name === 'disparador/getUIFlags') return ref({ isCreating: false });
    return ref([]);
  };

  beforeEach(() => {
    vi.clearAllMocks();
    dispatch = vi.fn().mockResolvedValue({ id: 99 });
    // By default both inboxes expose the same marketing template.
    templatesByInboxIds = vi.fn(() => [
      { name: 'promo_template', category: 'marketing' },
    ]);
    useStore.mockReturnValue({ dispatch });
    useStoreGetters.mockReturnValue(
      new Proxy({}, { get: (_t, prop) => getterMock(prop) })
    );
    useAlert.mockImplementation(() => {});
  });

  const fillRequired = async wrapper => {
    wrapper.vm.name = 'June reactivation';
    wrapper.vm.selectedLabels = ['vip'];
    await flushPromises();
  };

  it('lists only WhatsApp Cloud inboxes as checkboxes', () => {
    const wrapper = mountComponent();
    const checkboxes = wrapper.findAll('.stub-checkbox');
    expect(checkboxes).toHaveLength(2);
    expect(wrapper.html()).toContain('Cloud A');
    expect(wrapper.html()).toContain('Cloud B');
    expect(wrapper.html()).not.toContain('On-prem');
  });

  it('does not render any category picker (no manual category choice)', () => {
    const wrapper = mountComponent();
    // The category section heading stays (it labels the derived read-only badge),
    // but there is NO category ref/picker and no category option to choose from.
    expect(wrapper.vm.selectedCategory).toBeUndefined();
    expect(wrapper.html()).not.toContain('CATEGORY.UTILITY');
    expect(wrapper.html()).not.toContain('CATEGORY.AUTHENTICATION');
    // With no template selected the derived hint is shown, not a picker.
    expect(wrapper.html()).toContain('CATEGORY.DERIVED_HINT');
  });

  it('selecting multiple inboxes sends inbox_ids (array) + derived template_category', async () => {
    const wrapper = mountComponent();
    await fillRequired(wrapper);

    // Toggle both cloud inboxes on.
    const checkboxes = wrapper.findAll('.stub-checkbox');
    await checkboxes[0].trigger('change');
    await checkboxes[1].trigger('change');
    await flushPromises();

    // Pick the (intersection) template -> derives marketing.
    wrapper.vm.selectedTemplate = 'promo_template';
    await flushPromises();

    expect(wrapper.vm.isSubmitDisabled).toBe(false);

    await wrapper.find('.confirm-btn').trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith(
      'disparador/create',
      expect.objectContaining({
        inbox_ids: [1, 2],
        template_name: 'promo_template',
        template_category: 'marketing',
      })
    );
  });

  it('requests templates approved across ALL selected inboxes (intersection by ids)', async () => {
    const wrapper = mountComponent();
    const checkboxes = wrapper.findAll('.stub-checkbox');
    await checkboxes[0].trigger('change');
    await checkboxes[1].trigger('change');
    await flushPromises();

    expect(templatesByInboxIds).toHaveBeenCalledWith([1, 2]);
  });

  it('BLOCKS creation when the selected template has no category', async () => {
    templatesByInboxIds = vi.fn(() => [
      { name: 'no_category_template', category: null },
    ]);
    const wrapper = mountComponent();
    await fillRequired(wrapper);

    await wrapper.findAll('.stub-checkbox')[0].trigger('change');
    await flushPromises();
    wrapper.vm.selectedTemplate = 'no_category_template';
    await flushPromises();

    expect(wrapper.vm.hasMissingCategory).toBe(true);
    expect(wrapper.vm.isSubmitDisabled).toBe(true);
    expect(wrapper.html()).toContain('CATEGORY.MISSING');

    await wrapper.find('.confirm-btn').trigger('click');
    await flushPromises();
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('derives marketing for a MARKETING template and shows it read-only', async () => {
    const wrapper = mountComponent();
    await fillRequired(wrapper);
    await wrapper.findAll('.stub-checkbox')[0].trigger('change');
    await flushPromises();
    wrapper.vm.selectedTemplate = 'promo_template';
    await flushPromises();

    expect(wrapper.vm.derivedCategory).toBe('marketing');
    expect(wrapper.html()).toContain('CATEGORY.MARKETING');
  });

  it('resets the template when the inbox set changes', async () => {
    const wrapper = mountComponent();
    await wrapper.findAll('.stub-checkbox')[0].trigger('change');
    await flushPromises();
    wrapper.vm.selectedTemplate = 'promo_template';
    await flushPromises();

    // Toggling another inbox changes the intersection -> template resets.
    await wrapper.findAll('.stub-checkbox')[1].trigger('change');
    await flushPromises();
    expect(wrapper.vm.selectedTemplate).toBe('');
  });
});
