import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import Settings from '../Settings.vue';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import { DISPARADOR_SETTINGS_DEFAULTS } from '../helper/disparadorHelper';

vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables/useAccount');
vi.mock('dashboard/composables');

const mountComponent = () =>
  mount(Settings, {
    global: {
      mocks: { $t: key => key },
      plugins: [
        {
          install(app) {
            app.config.globalProperties.$t = key => key;
          },
        },
      ],
      stubs: {
        Input: {
          name: 'Input',
          props: ['modelValue'],
          emits: ['update:modelValue'],
          template:
            '<input class="stub-input" :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
        },
        TagInput: {
          name: 'TagInput',
          props: ['modelValue'],
          template: '<div class="stub-taginput" />',
        },
        Button: {
          name: 'Button',
          props: ['disabled', 'isLoading', 'label'],
          template:
            '<button class="stub-button" :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
        },
        RouterLink: { template: '<a><slot /></a>' },
      },
    },
  });

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

describe('Settings.vue (Disparador rules)', () => {
  const updateAccount = vi.fn();
  let currentAccount;

  beforeEach(() => {
    vi.clearAllMocks();
    currentAccount = ref({ id: 7, settings: {} });
    useStore.mockReturnValue({
      getters: { getCurrentAccountId: 7 },
      dispatch: vi.fn(),
    });
    useAccount.mockReturnValue({
      currentAccount,
      updateAccount,
    });
    useAlert.mockImplementation(() => {});
  });

  it('prefills the form with engine defaults when disparador_settings is unset', () => {
    const wrapper = mountComponent();
    const text = wrapper.html();
    // The save button is enabled (defaults are valid + steps present), proving
    // the form prefilled with effective values rather than blanks.
    const saveButton = wrapper.findAll('.stub-button').at(-1);
    expect(saveButton.attributes('disabled')).toBeUndefined();
    expect(text).toContain('DISPARADOR_MGMT.SETTINGS.HEADER');
  });

  it('saves all nine bindings via updateAccount with a top-level disparador_settings hash', async () => {
    updateAccount.mockResolvedValue();
    const wrapper = mountComponent();

    await wrapper.findAll('.stub-button').at(-1).trigger('click');
    await flushPromises();

    expect(updateAccount).toHaveBeenCalledTimes(1);
    const [payload, options] = updateAccount.mock.calls[0];
    expect(options).toEqual({ silent: true });
    expect(Object.keys(payload)).toEqual(['disparador_settings']);
    expect(payload.disparador_settings).toEqual({
      opt_out_label: DISPARADOR_SETTINGS_DEFAULTS.opt_out_label,
      opt_out_lgpd_key: DISPARADOR_SETTINGS_DEFAULTS.opt_out_lgpd_key,
      followup_locked_key: DISPARADOR_SETTINGS_DEFAULTS.followup_locked_key,
      window_closes_at_key: DISPARADOR_SETTINGS_DEFAULTS.window_closes_at_key,
      kanban_step_key: DISPARADOR_SETTINGS_DEFAULTS.kanban_step_key,
      whatsapp_invalid_at_key:
        DISPARADOR_SETTINGS_DEFAULTS.whatsapp_invalid_at_key,
      kanban_opt_out_steps: DISPARADOR_SETTINGS_DEFAULTS.kanban_opt_out_steps,
      dedup_window_days: DISPARADOR_SETTINGS_DEFAULTS.dedup_window_days,
      whatsapp_invalid_window_days:
        DISPARADOR_SETTINGS_DEFAULTS.whatsapp_invalid_window_days,
    });
    expect(useAlert).toHaveBeenCalledWith(
      'DISPARADOR_MGMT.SETTINGS.API.SUCCESS_MESSAGE'
    );
  });

  it('blocks save and does not dispatch when a required binding is blank', async () => {
    const wrapper = mountComponent();
    // Clear the opt-out label (first text input) → required validation fails.
    const firstInput = wrapper.findAll('.stub-input').at(0);
    await firstInput.setValue('');

    await wrapper.findAll('.stub-button').at(-1).trigger('click');
    await flushPromises();

    expect(updateAccount).not.toHaveBeenCalled();
  });

  it('surfaces an error toast when the update fails', async () => {
    updateAccount.mockRejectedValue(new Error('boom'));
    const wrapper = mountComponent();

    await wrapper.findAll('.stub-button').at(-1).trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'DISPARADOR_MGMT.SETTINGS.API.ERROR_MESSAGE'
    );
  });
});
