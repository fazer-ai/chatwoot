<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, integer, minValue } from '@vuelidate/validators';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TagInput from 'dashboard/components-next/taginput/TagInput.vue';
import { INPUT_TYPES } from 'dashboard/components-next/taginput/helper/tagInputHelper';
import { resolveDisparadorSettings } from './helper/disparadorHelper';

const { t } = useI18n();
const store = useStore();
const { currentAccount, updateAccount } = useAccount();

const isSubmitting = ref(false);

// String bindings — opt-out label + the 5 custom-attribute keys read by the
// audience engine. Prefilled with the EFFECTIVE value (default when unset).
const optOutLabel = ref('');
const optOutLgpdKey = ref('');
const followupLockedKey = ref('');
const windowClosesAtKey = ref('');
const kanbanStepKey = ref('');
const whatsappInvalidAtKey = ref('');
// Array binding — opt-out kanban stages.
const kanbanOptOutSteps = ref([]);
// Integer window bindings (days).
const dedupWindowDays = ref(0);
const whatsappInvalidWindowDays = ref(0);

// The settings sub-hash replaces wholesale on save, so every binding is required
// and the windows must be positive integers — mirrors RulesConfig's fallbacks so
// a blank/zero value never silently collapses a binding.
const positiveInteger = { required, integer, minValue: minValue(1) };
const rules = {
  optOutLabel: { required },
  optOutLgpdKey: { required },
  followupLockedKey: { required },
  windowClosesAtKey: { required },
  kanbanStepKey: { required },
  whatsappInvalidAtKey: { required },
  dedupWindowDays: positiveInteger,
  whatsappInvalidWindowDays: positiveInteger,
};

const v$ = useVuelidate(rules, {
  optOutLabel,
  optOutLgpdKey,
  followupLockedKey,
  windowClosesAtKey,
  kanbanStepKey,
  whatsappInvalidAtKey,
  dedupWindowDays,
  whatsappInvalidWindowDays,
});

const hasKanbanSteps = computed(() => kanbanOptOutSteps.value.length > 0);

const prefill = () => {
  const resolved = resolveDisparadorSettings(
    currentAccount.value?.settings?.disparador_settings
  );
  optOutLabel.value = resolved.opt_out_label;
  optOutLgpdKey.value = resolved.opt_out_lgpd_key;
  followupLockedKey.value = resolved.followup_locked_key;
  windowClosesAtKey.value = resolved.window_closes_at_key;
  kanbanStepKey.value = resolved.kanban_step_key;
  whatsappInvalidAtKey.value = resolved.whatsapp_invalid_at_key;
  kanbanOptOutSteps.value = [...resolved.kanban_opt_out_steps];
  dedupWindowDays.value = resolved.dedup_window_days;
  whatsappInvalidWindowDays.value = resolved.whatsapp_invalid_window_days;
};

// The account is loaded into the store before this route mounts; prefill once it
// resolves (and re-prefill if it changes underneath us).
watch(currentAccount, prefill, { immediate: true });

// key is always a literal i18n string passed by the template; the dynamic-key
// rule can't see that, so it's disabled here (same pattern as statusText in
// Index.vue).
const fieldError = (field, key) =>
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  v$.value[field].$error ? t(key) : '';

const isSaveDisabled = computed(
  () => v$.value.$invalid || !hasKanbanSteps.value || isSubmitting.value
);

const save = async () => {
  v$.value.$touch();
  if (isSaveDisabled.value) return;

  isSubmitting.value = true;
  try {
    // Send all 9 keys at the top level: the account-update API permits
    // `disparador_settings` and merges the whole sub-hash, so omitting a key
    // would drop it. The kanban steps stay strings to match the jsonb-text
    // comparison the engine performs.
    await updateAccount(
      {
        disparador_settings: {
          opt_out_label: optOutLabel.value,
          opt_out_lgpd_key: optOutLgpdKey.value,
          followup_locked_key: followupLockedKey.value,
          window_closes_at_key: windowClosesAtKey.value,
          kanban_step_key: kanbanStepKey.value,
          whatsapp_invalid_at_key: whatsappInvalidAtKey.value,
          kanban_opt_out_steps: kanbanOptOutSteps.value.map(String),
          dedup_window_days: Number(dedupWindowDays.value),
          whatsapp_invalid_window_days: Number(whatsappInvalidWindowDays.value),
        },
      },
      { silent: true }
    );
    useAlert(t('DISPARADOR_MGMT.SETTINGS.API.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('DISPARADOR_MGMT.SETTINGS.API.ERROR_MESSAGE'));
  } finally {
    isSubmitting.value = false;
  }
};

const backRoute = computed(() => ({
  name: 'disparador_list',
  params: { accountId: store.getters.getCurrentAccountId },
}));
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header class="sticky top-0 z-10 px-6">
      <div class="w-full max-w-3xl mx-auto">
        <div class="flex items-center justify-between w-full h-20 gap-2">
          <div class="flex flex-col gap-1">
            <span class="text-heading-1 text-n-slate-12">
              {{ t('DISPARADOR_MGMT.SETTINGS.HEADER') }}
            </span>
          </div>
          <router-link :to="backRoute">
            <Button
              variant="faded"
              color="slate"
              size="sm"
              icon="i-lucide-arrow-left"
              :label="t('DISPARADOR_MGMT.SETTINGS.BACK')"
            />
          </router-link>
        </div>
      </div>
    </header>

    <main class="flex-1 px-6 overflow-y-auto">
      <div class="flex flex-col w-full max-w-3xl gap-6 py-4 mx-auto">
        <p class="mb-0 text-body-para text-n-slate-11">
          {{ t('DISPARADOR_MGMT.SETTINGS.DESC') }}
        </p>

        <section
          class="flex flex-col w-full gap-5 px-5 py-4 outline outline-1 outline-n-container rounded-xl bg-n-solid-2"
        >
          <div class="flex flex-col gap-1">
            <h3 class="text-heading-2 text-n-slate-12">
              {{ t('DISPARADOR_MGMT.SETTINGS.OPT_OUT.TITLE') }}
            </h3>
            <p class="mb-0 text-body-para text-n-slate-11">
              {{ t('DISPARADOR_MGMT.SETTINGS.OPT_OUT.NOTE') }}
            </p>
          </div>

          <Input
            v-model="optOutLabel"
            :label="t('DISPARADOR_MGMT.SETTINGS.OPT_OUT.LABEL.LABEL')"
            :placeholder="
              t('DISPARADOR_MGMT.SETTINGS.OPT_OUT.LABEL.PLACEHOLDER')
            "
            :message="
              fieldError(
                'optOutLabel',
                'DISPARADOR_MGMT.SETTINGS.VALIDATION.REQUIRED'
              ) || t('DISPARADOR_MGMT.SETTINGS.OPT_OUT.LABEL.HINT')
            "
            :message-type="v$.optOutLabel.$error ? 'error' : 'info'"
            @blur="v$.optOutLabel.$touch"
          />

          <div class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('DISPARADOR_MGMT.SETTINGS.OPT_OUT.STEPS.LABEL') }}
            </span>
            <div
              class="w-full px-3 py-2 rounded-lg outline outline-1 outline-n-weak bg-n-alpha-black2"
            >
              <TagInput
                v-model="kanbanOptOutSteps"
                :type="INPUT_TYPES.TEXT"
                allow-create
                :auto-open-dropdown="false"
                :placeholder="
                  t('DISPARADOR_MGMT.SETTINGS.OPT_OUT.STEPS.PLACEHOLDER')
                "
              />
            </div>
            <p
              v-if="!hasKanbanSteps"
              class="mb-0 text-sm text-n-ruby-9 dark:text-n-ruby-9"
            >
              {{ t('DISPARADOR_MGMT.SETTINGS.VALIDATION.STEPS_REQUIRED') }}
            </p>
            <p v-else class="mb-0 text-sm text-n-slate-11">
              {{ t('DISPARADOR_MGMT.SETTINGS.OPT_OUT.STEPS.HINT') }}
            </p>
          </div>
        </section>

        <section
          class="flex flex-col w-full gap-5 px-5 py-4 outline outline-1 outline-n-container rounded-xl bg-n-solid-2"
        >
          <div class="flex flex-col gap-1">
            <h3 class="text-heading-2 text-n-slate-12">
              {{ t('DISPARADOR_MGMT.SETTINGS.KEYS.TITLE') }}
            </h3>
            <p class="mb-0 text-body-para text-n-slate-11">
              {{ t('DISPARADOR_MGMT.SETTINGS.KEYS.NOTE') }}
            </p>
          </div>

          <Input
            v-model="optOutLgpdKey"
            :label="t('DISPARADOR_MGMT.SETTINGS.KEYS.OPT_OUT_LGPD.LABEL')"
            :placeholder="
              t('DISPARADOR_MGMT.SETTINGS.KEYS.OPT_OUT_LGPD.PLACEHOLDER')
            "
            :message="
              fieldError(
                'optOutLgpdKey',
                'DISPARADOR_MGMT.SETTINGS.VALIDATION.REQUIRED'
              ) || t('DISPARADOR_MGMT.SETTINGS.KEYS.OPT_OUT_LGPD.HINT')
            "
            :message-type="v$.optOutLgpdKey.$error ? 'error' : 'info'"
            @blur="v$.optOutLgpdKey.$touch"
          />

          <Input
            v-model="followupLockedKey"
            :label="t('DISPARADOR_MGMT.SETTINGS.KEYS.FOLLOWUP_LOCKED.LABEL')"
            :placeholder="
              t('DISPARADOR_MGMT.SETTINGS.KEYS.FOLLOWUP_LOCKED.PLACEHOLDER')
            "
            :message="
              fieldError(
                'followupLockedKey',
                'DISPARADOR_MGMT.SETTINGS.VALIDATION.REQUIRED'
              ) || t('DISPARADOR_MGMT.SETTINGS.KEYS.FOLLOWUP_LOCKED.HINT')
            "
            :message-type="v$.followupLockedKey.$error ? 'error' : 'info'"
            @blur="v$.followupLockedKey.$touch"
          />

          <Input
            v-model="windowClosesAtKey"
            :label="t('DISPARADOR_MGMT.SETTINGS.KEYS.WINDOW_CLOSES_AT.LABEL')"
            :placeholder="
              t('DISPARADOR_MGMT.SETTINGS.KEYS.WINDOW_CLOSES_AT.PLACEHOLDER')
            "
            :message="
              fieldError(
                'windowClosesAtKey',
                'DISPARADOR_MGMT.SETTINGS.VALIDATION.REQUIRED'
              ) || t('DISPARADOR_MGMT.SETTINGS.KEYS.WINDOW_CLOSES_AT.HINT')
            "
            :message-type="v$.windowClosesAtKey.$error ? 'error' : 'info'"
            @blur="v$.windowClosesAtKey.$touch"
          />

          <Input
            v-model="kanbanStepKey"
            :label="t('DISPARADOR_MGMT.SETTINGS.KEYS.KANBAN_STEP.LABEL')"
            :placeholder="
              t('DISPARADOR_MGMT.SETTINGS.KEYS.KANBAN_STEP.PLACEHOLDER')
            "
            :message="
              fieldError(
                'kanbanStepKey',
                'DISPARADOR_MGMT.SETTINGS.VALIDATION.REQUIRED'
              ) || t('DISPARADOR_MGMT.SETTINGS.KEYS.KANBAN_STEP.HINT')
            "
            :message-type="v$.kanbanStepKey.$error ? 'error' : 'info'"
            @blur="v$.kanbanStepKey.$touch"
          />

          <Input
            v-model="whatsappInvalidAtKey"
            :label="
              t('DISPARADOR_MGMT.SETTINGS.KEYS.WHATSAPP_INVALID_AT.LABEL')
            "
            :placeholder="
              t('DISPARADOR_MGMT.SETTINGS.KEYS.WHATSAPP_INVALID_AT.PLACEHOLDER')
            "
            :message="
              fieldError(
                'whatsappInvalidAtKey',
                'DISPARADOR_MGMT.SETTINGS.VALIDATION.REQUIRED'
              ) || t('DISPARADOR_MGMT.SETTINGS.KEYS.WHATSAPP_INVALID_AT.HINT')
            "
            :message-type="v$.whatsappInvalidAtKey.$error ? 'error' : 'info'"
            @blur="v$.whatsappInvalidAtKey.$touch"
          />
        </section>

        <section
          class="flex flex-col w-full gap-5 px-5 py-4 outline outline-1 outline-n-container rounded-xl bg-n-solid-2"
        >
          <div class="flex flex-col gap-1">
            <h3 class="text-heading-2 text-n-slate-12">
              {{ t('DISPARADOR_MGMT.SETTINGS.WINDOWS.TITLE') }}
            </h3>
            <p class="mb-0 text-body-para text-n-slate-11">
              {{ t('DISPARADOR_MGMT.SETTINGS.WINDOWS.NOTE') }}
            </p>
          </div>

          <Input
            v-model="dedupWindowDays"
            type="number"
            min="1"
            :label="t('DISPARADOR_MGMT.SETTINGS.WINDOWS.DEDUP.LABEL')"
            :placeholder="
              t('DISPARADOR_MGMT.SETTINGS.WINDOWS.DEDUP.PLACEHOLDER')
            "
            :message="
              fieldError(
                'dedupWindowDays',
                'DISPARADOR_MGMT.SETTINGS.VALIDATION.POSITIVE_INTEGER'
              ) || t('DISPARADOR_MGMT.SETTINGS.WINDOWS.DEDUP.HINT')
            "
            :message-type="v$.dedupWindowDays.$error ? 'error' : 'info'"
            @blur="v$.dedupWindowDays.$touch"
          />

          <Input
            v-model="whatsappInvalidWindowDays"
            type="number"
            min="1"
            :label="
              t('DISPARADOR_MGMT.SETTINGS.WINDOWS.WHATSAPP_INVALID.LABEL')
            "
            :placeholder="
              t('DISPARADOR_MGMT.SETTINGS.WINDOWS.WHATSAPP_INVALID.PLACEHOLDER')
            "
            :message="
              fieldError(
                'whatsappInvalidWindowDays',
                'DISPARADOR_MGMT.SETTINGS.VALIDATION.POSITIVE_INTEGER'
              ) || t('DISPARADOR_MGMT.SETTINGS.WINDOWS.WHATSAPP_INVALID.HINT')
            "
            :message-type="
              v$.whatsappInvalidWindowDays.$error ? 'error' : 'info'
            "
            @blur="v$.whatsappInvalidWindowDays.$touch"
          />
        </section>

        <div class="flex justify-end">
          <Button
            :label="t('DISPARADOR_MGMT.SETTINGS.SAVE')"
            :is-loading="isSubmitting"
            :disabled="isSaveDisabled"
            @click="save"
          />
        </div>
      </div>
    </main>
  </div>
</template>
