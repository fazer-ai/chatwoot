<script setup>
import { computed, ref } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const props = defineProps({
  inboxId: {
    type: [Number, String],
    required: true,
  },
});

const store = useStore();
const { t } = useI18n();

const uiFlags = useMapGetter('inboxes/getUIFlags');
const isSubmitting = computed(() => uiFlags.value.isSubmittingTemplate);

const NAME_REGEX = /^[a-z0-9_]+$/;

const dialogRef = ref(null);

const name = ref('');
const language = ref('pt_BR');
const category = ref('UTILITY');
const body = ref('');
const footer = ref('');
const samples = ref([]);
const isDirty = ref(false);

const categoryOptions = computed(() => [
  {
    value: 'MARKETING',
    label: t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.CATEGORY.MARKETING'),
  },
  {
    value: 'UTILITY',
    label: t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.CATEGORY.UTILITY'),
  },
]);

// Distinct {{N}} placeholder numbers found in the body, sorted ascending.
const variableNumbers = computed(() => {
  const matches = body.value.match(/\{\{(\d+)\}\}/g) || [];
  const numbers = new Set(
    matches.map(token => Number(token.replace(/\D/g, '')))
  );
  return [...numbers].sort((a, b) => a - b);
});

// One sample per variable.
const variableCount = computed(() => variableNumbers.value.length);

// Meta requires variables numbered sequentially from 1 ({{1}}, {{2}}, ...).
// Our example array is emitted positionally, so a gap or non-1-based set would
// desync from Meta's numbering and trigger a 422. Empty set is valid (no vars).
const areVariablesSequential = computed(() =>
  variableNumbers.value.every((number, index) => number === index + 1)
);

const onBodyUpdate = value => {
  body.value = value;
  const count = variableCount.value;
  // Keep the samples array length in sync with the number of variables.
  if (samples.value.length > count) {
    samples.value = samples.value.slice(0, count);
  } else {
    while (samples.value.length < count) {
      samples.value.push('');
    }
  }
};

const isNameValid = computed(() => NAME_REGEX.test(name.value));
const areSamplesValid = computed(() =>
  samples.value.every(sample => sample.trim().length > 0)
);

const nameError = computed(() =>
  isDirty.value && !isNameValid.value
    ? t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.NAME.ERROR')
    : ''
);
const languageError = computed(() =>
  isDirty.value && !language.value.trim()
    ? t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.LANGUAGE.ERROR')
    : ''
);
const bodyError = computed(() =>
  isDirty.value && !body.value.trim()
    ? t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.BODY.ERROR')
    : ''
);
const variablesError = computed(() =>
  isDirty.value && !areVariablesSequential.value
    ? t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.BODY.VARIABLES_ERROR')
    : ''
);
const samplesError = computed(() =>
  isDirty.value && !areSamplesValid.value
    ? t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.SAMPLES.ERROR')
    : ''
);

const isFormValid = computed(
  () =>
    isNameValid.value &&
    language.value.trim() &&
    body.value.trim() &&
    areVariablesSequential.value &&
    areSamplesValid.value
);

// Keep the confirm button clickable while invalid so the first click can surface
// the inline validation errors; only block it while a submit is in flight.
const isSubmitDisabled = computed(() => isSubmitting.value);

const buildPayload = () => {
  const components = [
    {
      type: 'BODY',
      text: body.value,
    },
  ];
  // Meta rejects an empty example block, so only attach it when there are
  // variables to exemplify.
  if (variableCount.value > 0) {
    components[0].example = {
      body_text: [samples.value.map(sample => sample.trim())],
    };
  }
  if (footer.value.trim()) {
    components.push({ type: 'FOOTER', text: footer.value.trim() });
  }
  return {
    name: name.value,
    language: language.value.trim(),
    category: category.value,
    components,
  };
};

const reset = () => {
  name.value = '';
  language.value = 'pt_BR';
  category.value = 'UTILITY';
  body.value = '';
  footer.value = '';
  samples.value = [];
  isDirty.value = false;
};

const submit = async () => {
  isDirty.value = true;
  if (!isFormValid.value || isSubmitting.value) return;

  try {
    const result = await store.dispatch('inboxes/submitTemplate', {
      inboxId: props.inboxId,
      payload: buildPayload(),
    });
    const status = result?.status;
    useAlert(
      status
        ? t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.SUCCESS_WITH_STATUS', {
            status,
          })
        : t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.SUCCESS')
    );
    dialogRef.value?.close();
  } catch (error) {
    useAlert(error?.message || t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.ERROR'));
  }
};

const open = () => {
  reset();
  dialogRef.value?.open();
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.TITLE')"
    :description="t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.DESCRIPTION')"
    :confirm-button-label="t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.BUTTON')"
    :disable-confirm-button="isSubmitDisabled"
    :is-loading="isSubmitting"
    width="xl"
    overflow-y-auto
    @confirm="submit"
  >
    <div class="flex flex-col gap-5">
      <Input
        v-model="name"
        :label="t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.NAME.LABEL')"
        :placeholder="
          t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.NAME.PLACEHOLDER')
        "
        :message="
          nameError || t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.NAME.HINT')
        "
        :message-type="nameError ? 'error' : 'info'"
      />

      <Input
        v-model="language"
        :label="t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.LANGUAGE.LABEL')"
        :placeholder="
          t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.LANGUAGE.PLACEHOLDER')
        "
        :message="languageError"
        :message-type="languageError ? 'error' : 'info'"
      />

      <div class="flex flex-col gap-1">
        <span class="text-heading-3 text-n-slate-12">
          {{ t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.CATEGORY.LABEL') }}
        </span>
        <Select
          v-model="category"
          class="!w-full [&>select]:w-full"
          :options="categoryOptions"
        />
      </div>

      <TextArea
        :model-value="body"
        :label="t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.BODY.LABEL')"
        :placeholder="
          t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.BODY.PLACEHOLDER')
        "
        :message="
          bodyError ||
          variablesError ||
          t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.BODY.HINT')
        "
        :message-type="bodyError || variablesError ? 'error' : 'info'"
        @update:model-value="onBodyUpdate"
      />

      <div v-if="samples.length" class="flex flex-col gap-3">
        <span class="text-heading-3 text-n-slate-12">
          {{ t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.SAMPLES.HINT') }}
        </span>
        <Input
          v-for="(sample, index) in samples"
          :key="index"
          v-model="samples[index]"
          :label="
            t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.SAMPLES.LABEL', {
              index: index + 1,
            })
          "
          :placeholder="
            t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.SAMPLES.PLACEHOLDER')
          "
        />
        <p v-if="samplesError" class="mb-0 text-label-small text-n-ruby-9">
          {{ samplesError }}
        </p>
      </div>

      <Input
        v-model="footer"
        :label="t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.FOOTER.LABEL')"
        :placeholder="
          t('INBOX_MGMT.WHATSAPP_TEMPLATES.SUBMIT.FOOTER.PLACEHOLDER')
        "
      />
    </div>
  </Dialog>
</template>
