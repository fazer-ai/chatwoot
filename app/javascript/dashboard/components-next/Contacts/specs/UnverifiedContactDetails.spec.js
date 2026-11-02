import { flushPromises, mount } from '@vue/test-utils';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ContactAPI from 'dashboard/api/contacts';
import UnverifiedContactDetails from '../UnverifiedContactDetails.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}:${params.name}` : key),
  }),
}));
vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables');
vi.mock('dashboard/api/contacts', () => ({ default: { search: vi.fn() } }));

const dispatch = vi.fn();

const mountWith = (additionalAttributes, searchPayload = []) => {
  ContactAPI.search.mockResolvedValue({ data: { payload: searchPayload } });
  return mount(UnverifiedContactDetails, {
    props: {
      contact: { id: 7, additional_attributes: additionalAttributes },
    },
    global: {
      stubs: {
        RouterLink: {
          props: ['to'],
          template: '<a :data-contact="to.params.contactId"><slot /></a>',
        },
        Button: {
          props: ['label'],
          emits: ['click'],
          template: '<button @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });
};

const buttonLabeled = (wrapper, label) =>
  wrapper.findAll('button').find(button => button.text() === label);

describe('UnverifiedContactDetails', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    useStore.mockReturnValue({ dispatch });
    dispatch.mockResolvedValue();
  });

  it('renders nothing when the contact has no unverified value', async () => {
    const wrapper = mountWith({ city: 'Recife' });
    await flushPromises();

    expect(wrapper.html()).toBe('<!--v-if-->');
  });

  it('confirms a value nobody else holds onto the contact and clears the claim', async () => {
    const wrapper = mountWith({ claimed_phone_number: '+5511977776666' }, [
      { id: 7, phone_number: '+5511977776666' },
      { id: 9, phone_number: '+5511977776660' },
    ]);
    await flushPromises();

    expect(wrapper.text()).toContain('+5511977776666');
    await buttonLabeled(
      wrapper,
      'CONTACT_PANEL.UNVERIFIED_DETAILS.CONFIRM'
    ).trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('contacts/update', {
      id: 7,
      phone_number: '+5511977776666',
      additional_attributes: { claimed_phone_number: null },
    });
    expect(useAlert).toHaveBeenCalledWith(
      'CONTACT_PANEL.UNVERIFIED_DETAILS.CONFIRMED'
    );
    expect(wrapper.emitted('settled')).toHaveLength(1);
  });

  it('points to the contact that already holds the value instead of offering to confirm it', async () => {
    const wrapper = mountWith({ claimed_email: 'Customer@Example.com' }, [
      { id: 9, name: 'Customer', email: 'customer@example.com' },
    ]);
    await flushPromises();

    const link = wrapper.find('a');
    expect(link.attributes('data-contact')).toBe('9');
    expect(link.text()).toBe(
      'CONTACT_PANEL.UNVERIFIED_DETAILS.HELD_BY:Customer'
    );
    expect(
      buttonLabeled(wrapper, 'CONTACT_PANEL.UNVERIFIED_DETAILS.CONFIRM')
    ).toBeUndefined();
  });

  it('reads the camelized contact the contact page gets from the store', async () => {
    ContactAPI.search.mockResolvedValue({ data: { payload: [] } });
    const wrapper = mount(UnverifiedContactDetails, {
      props: {
        contact: {
          id: 7,
          additionalAttributes: { claimedPhoneNumber: '+5511977776666' },
        },
      },
      global: { stubs: { RouterLink: true, Button: true } },
    });
    await flushPromises();

    expect(wrapper.text()).toContain('+5511977776666');
  });

  it('dismisses a claim without touching the contact field', async () => {
    const wrapper = mountWith({ claimed_email: 'someone@example.com' });
    await flushPromises();

    await buttonLabeled(
      wrapper,
      'CONTACT_PANEL.UNVERIFIED_DETAILS.DISMISS'
    ).trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('contacts/update', {
      id: 7,
      additional_attributes: { claimed_email: null },
    });
  });
});
