<script setup>
import { computed, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TagInput from 'dashboard/components-next/taginput/TagInput.vue';
import { INPUT_TYPES } from 'dashboard/components-next/taginput/helper/tagInputHelper';

const emit = defineEmits(['created']);

const { t } = useI18n();
const route = useRoute();
const store = useStore();
const getters = useStoreGetters();

const dialogRef = ref(null);

const name = ref('');
const description = ref('');
const selectedInboxId = ref('');
const selectedTemplate = ref('');
// Mirrors the backend disparo template_category enum (lowercase). Defaults to
// 'utility' to match the backend default. MARKETING is what makes the G2
// marketing-cooldown gate reachable for an operator.
const selectedCategory = ref('utility');
// Mirror the backend conversation_status enum (lowercase). Default matches the
// model default (open).
const selectedConversationStatus = ref('open');
const kanbanSteps = ref([]);
const selectedLabels = ref([]);

const rules = {
  name: { required },
  selectedInboxId: { required },
  selectedTemplate: { required },
};
const v$ = useVuelidate(rules, { name, selectedInboxId, selectedTemplate });

const uiFlags = computed(() => getters['disparador/getUIFlags'].value);
const isCreating = computed(() => uiFlags.value.isCreating);

// Beta 0 is exclusive_cloud: only WhatsApp Cloud inboxes are valid. The API
// rejects anything else with unsupported_inbox_provider (422), so the select is
// filtered to Cloud only at the source.
const cloudInboxes = computed(() =>
  getters['inboxes/getInboxes'].value.filter(
    inbox =>
      inbox.channel_type === INBOX_TYPES.WHATSAPP &&
      inbox.provider === 'whatsapp_cloud'
  )
);

const inboxOptions = computed(() =>
  cloudInboxes.value.map(inbox => ({ value: inbox.id, label: inbox.name }))
);

const hasCloudInbox = computed(() => cloudInboxes.value.length > 0);

const templates = computed(() => {
  if (!selectedInboxId.value) return [];
  return getters['inboxes/getDisparadorWhatsAppTemplates'].value(
    selectedInboxId.value
  );
});

const templateOptions = computed(() =>
  templates.value.map(template => ({
    value: template.name,
    label: template.name,
  }))
);

const categoryOptions = computed(() => [
  {
    value: 'marketing',
    label: t('DISPARADOR_MGMT.CREATE.FORM.CATEGORY.MARKETING'),
  },
  {
    value: 'utility',
    label: t('DISPARADOR_MGMT.CREATE.FORM.CATEGORY.UTILITY'),
  },
  {
    value: 'authentication',
    label: t('DISPARADOR_MGMT.CREATE.FORM.CATEGORY.AUTHENTICATION'),
  },
]);

const conversationStatusOptions = computed(() => [
  {
    value: 'open',
    label: t('DISPARADOR_MGMT.CREATE.FORM.CONVERSATION_STATUS.OPEN'),
  },
  {
    value: 'all',
    label: t('DISPARADOR_MGMT.CREATE.FORM.CONVERSATION_STATUS.ALL'),
  },
]);

// The inbox select is already Cloud-only, so a selected inbox is a Cloud inbox.
// Link straight to its settings Templates tab to create/manage templates.
const manageTemplatesRoute = computed(() => {
  if (!selectedInboxId.value) return null;
  return {
    name: 'settings_inbox_show',
    params: {
      accountId: route.params.accountId,
      inboxId: selectedInboxId.value,
      tab: 'whatsapp-templates',
    },
  };
});

const labelMenuItems = computed(() =>
  getters['labels/getLabels'].value.map(label => ({
    action: 'select',
    value: label.title,
    label: label.title,
  }))
);

const hasAudience = computed(
  () => kanbanSteps.value.length > 0 || selectedLabels.value.length > 0
);

const isSubmitDisabled = computed(
  () => v$.value.$invalid || !hasAudience.value || isCreating.value
);

const onInboxChange = () => {
  selectedTemplate.value = '';
  v$.value.selectedTemplate.$reset();
};

const resolveCreateError = message => {
  if (message === 'unsupported_inbox_provider') {
    return t('DISPARADOR_MGMT.CREATE.API.ERRORS.UNSUPPORTED_INBOX_PROVIDER');
  }
  if (message === 'invalid_audience_filter') {
    return t('DISPARADOR_MGMT.CREATE.API.ERRORS.INVALID_AUDIENCE_FILTER');
  }
  if (message === 'invalid_template') {
    return t('DISPARADOR_MGMT.CREATE.API.ERRORS.INVALID_TEMPLATE');
  }
  return message || t('DISPARADOR_MGMT.CREATE.API.ERROR_MESSAGE');
};

const submit = async () => {
  v$.value.$touch();
  if (isSubmitDisabled.value) return;

  try {
    const disparo = await store.dispatch('disparador/create', {
      name: name.value,
      description: description.value,
      template_name: selectedTemplate.value,
      template_category: selectedCategory.value,
      conversation_status: selectedConversationStatus.value,
      inbox_ids: [selectedInboxId.value],
      audience_filter: {
        kanban_steps: kanbanSteps.value,
        label: selectedLabels.value,
      },
    });
    useAlert(t('DISPARADOR_MGMT.CREATE.API.SUCCESS_MESSAGE'));
    emit('created', disparo);
    dialogRef.value?.close();
  } catch (error) {
    useAlert(resolveCreateError(error?.message));
  }
};

const open = () => {
  name.value = '';
  description.value = '';
  selectedInboxId.value = '';
  selectedTemplate.value = '';
  selectedCategory.value = 'utility';
  selectedConversationStatus.value = 'open';
  kanbanSteps.value = [];
  selectedLabels.value = [];
  v$.value.$reset();
  dialogRef.value?.open();
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('DISPARADOR_MGMT.CREATE.TITLE')"
    :description="t('DISPARADOR_MGMT.CREATE.DESC')"
    :confirm-button-label="t('DISPARADOR_MGMT.CREATE.FORM.SUBMIT')"
    :cancel-button-label="t('DISPARADOR_MGMT.CREATE.FORM.CANCEL')"
    :disable-confirm-button="isSubmitDisabled"
    :is-loading="isCreating"
    width="xl"
    overflow-y-auto
    @confirm="submit"
  >
    <div class="flex flex-col gap-5">
      <Input
        v-model="name"
        :label="t('DISPARADOR_MGMT.CREATE.FORM.NAME.LABEL')"
        :placeholder="t('DISPARADOR_MGMT.CREATE.FORM.NAME.PLACEHOLDER')"
        :message="
          v$.name.$error ? t('DISPARADOR_MGMT.CREATE.FORM.NAME.ERROR') : ''
        "
        :message-type="v$.name.$error ? 'error' : 'info'"
        @blur="v$.name.$touch"
      />

      <Input
        v-model="description"
        :label="t('DISPARADOR_MGMT.CREATE.FORM.DESCRIPTION.LABEL')"
        :placeholder="t('DISPARADOR_MGMT.CREATE.FORM.DESCRIPTION.PLACEHOLDER')"
      />

      <div class="flex flex-col gap-1">
        <span class="text-heading-3 text-n-slate-12">
          {{ t('DISPARADOR_MGMT.CREATE.FORM.INBOX.LABEL') }}
        </span>
        <Select
          v-if="hasCloudInbox"
          v-model="selectedInboxId"
          class="!w-full [&>select]:w-full"
          :options="inboxOptions"
          :placeholder="t('DISPARADOR_MGMT.CREATE.FORM.INBOX.PLACEHOLDER')"
          :error="
            v$.selectedInboxId.$error
              ? t('DISPARADOR_MGMT.CREATE.FORM.INBOX.ERROR')
              : ''
          "
          @update:model-value="onInboxChange"
        />
        <p v-else class="mb-0 text-sm text-n-slate-11">
          {{ t('DISPARADOR_MGMT.CREATE.FORM.INBOX.EMPTY') }}
        </p>
      </div>

      <div class="flex flex-col gap-1">
        <div class="flex items-center justify-between gap-2">
          <span class="text-heading-3 text-n-slate-12">
            {{ t('DISPARADOR_MGMT.CREATE.FORM.TEMPLATE.LABEL') }}
          </span>
          <router-link
            v-if="manageTemplatesRoute"
            :to="manageTemplatesRoute"
            target="_blank"
            class="text-sm font-medium text-n-blue-text hover:underline"
          >
            {{ t('DISPARADOR_MGMT.CREATE.FORM.TEMPLATE.MANAGE_LINK') }}
          </router-link>
        </div>
        <Select
          v-if="selectedInboxId && templateOptions.length"
          v-model="selectedTemplate"
          class="!w-full [&>select]:w-full"
          :options="templateOptions"
          :placeholder="t('DISPARADOR_MGMT.CREATE.FORM.TEMPLATE.PLACEHOLDER')"
          :error="
            v$.selectedTemplate.$error
              ? t('DISPARADOR_MGMT.CREATE.FORM.TEMPLATE.ERROR')
              : ''
          "
          @blur="v$.selectedTemplate.$touch"
        />
        <p v-else class="mb-0 text-sm text-n-slate-11">
          {{ t('DISPARADOR_MGMT.CREATE.FORM.TEMPLATE.EMPTY') }}
        </p>
      </div>

      <div class="flex flex-col gap-1">
        <span class="text-heading-3 text-n-slate-12">
          {{ t('DISPARADOR_MGMT.CREATE.FORM.CATEGORY.LABEL') }}
        </span>
        <Select
          v-model="selectedCategory"
          class="!w-full [&>select]:w-full"
          :options="categoryOptions"
        />
      </div>

      <div class="flex flex-col gap-1">
        <span class="text-heading-3 text-n-slate-12">
          {{ t('DISPARADOR_MGMT.CREATE.FORM.CONVERSATION_STATUS.LABEL') }}
        </span>
        <Select
          v-model="selectedConversationStatus"
          class="!w-full [&>select]:w-full"
          :options="conversationStatusOptions"
        />
      </div>

      <div class="flex flex-col gap-1">
        <span class="text-heading-3 text-n-slate-12">
          {{ t('DISPARADOR_MGMT.CREATE.FORM.KANBAN_STEPS.LABEL') }}
        </span>
        <div
          class="w-full px-3 py-2 rounded-lg outline outline-1 outline-n-weak bg-n-alpha-black2"
        >
          <TagInput
            v-model="kanbanSteps"
            :type="INPUT_TYPES.TEXT"
            allow-create
            :auto-open-dropdown="false"
            :placeholder="
              t('DISPARADOR_MGMT.CREATE.FORM.KANBAN_STEPS.PLACEHOLDER')
            "
          />
        </div>
      </div>

      <div class="flex flex-col gap-1">
        <span class="text-heading-3 text-n-slate-12">
          {{ t('DISPARADOR_MGMT.CREATE.FORM.LABELS.LABEL') }}
        </span>
        <div
          class="w-full px-3 py-2 rounded-lg outline outline-1 outline-n-weak bg-n-alpha-black2"
        >
          <TagInput
            v-model="selectedLabels"
            :type="INPUT_TYPES.TEXT"
            show-dropdown
            :menu-items="labelMenuItems"
            :auto-open-dropdown="false"
            :placeholder="t('DISPARADOR_MGMT.CREATE.FORM.LABELS.PLACEHOLDER')"
          />
        </div>
      </div>

      <p v-if="!hasAudience" class="mb-0 text-sm text-n-amber-11">
        {{ t('DISPARADOR_MGMT.CREATE.FORM.AUDIENCE_HINT') }}
      </p>
    </div>
  </Dialog>
</template>
