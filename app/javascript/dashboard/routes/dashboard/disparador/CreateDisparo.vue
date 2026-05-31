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
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import TagInput from 'dashboard/components-next/taginput/TagInput.vue';
import { INPUT_TYPES } from 'dashboard/components-next/taginput/helper/tagInputHelper';
import { templateCategoryLabelKey } from './helper/disparadorHelper';

const emit = defineEmits(['created']);

const { t } = useI18n();
const route = useRoute();
const store = useStore();
const getters = useStoreGetters();

const dialogRef = ref(null);

const name = ref('');
const description = ref('');
// GAP D: a disparo can target multiple WhatsApp Cloud inboxes; the template +
// derived category must hold across ALL of them. Holds the selected inbox ids.
const selectedInboxIds = ref([]);
const selectedTemplate = ref('');
// Mirror the backend conversation_status enum (lowercase). Default matches the
// model default (open).
const selectedConversationStatus = ref('open');
const kanbanSteps = ref([]);
const selectedLabels = ref([]);

const rules = {
  name: { required },
  // GAP D: at least one inbox is required (an empty array is invalid).
  selectedInboxIds: { required },
  selectedTemplate: { required },
};
const v$ = useVuelidate(rules, { name, selectedInboxIds, selectedTemplate });

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

const hasCloudInbox = computed(() => cloudInboxes.value.length > 0);

const isInboxSelected = inboxId => selectedInboxIds.value.includes(inboxId);

// GAP D: intersection of templates approved in ALL selected inboxes, each entry
// carrying its derived (mapped) category — or null when absent/inconsistent.
const templates = computed(() => {
  if (!selectedInboxIds.value.length) return [];
  return getters['inboxes/getDisparadorWhatsAppTemplates'].value(
    selectedInboxIds.value
  );
});

const templateOptions = computed(() =>
  templates.value.map(template => ({
    value: template.name,
    label: template.name,
  }))
);

// GAP A: the category is DERIVED from the selected template (never picked). It
// is the real, backend-matching category of the approved template across every
// selected inbox, or null when the template carries no category (or disagrees
// across inboxes) — which blocks creation.
const derivedCategory = computed(() => {
  if (!selectedTemplate.value) return undefined;
  const entry = templates.value.find(
    template => template.name === selectedTemplate.value
  );
  return entry ? entry.category : undefined;
});

const derivedCategoryLabel = computed(() => {
  const key = templateCategoryLabelKey(derivedCategory.value);
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  return key ? t(key) : '';
});

// True only when a template is selected AND it has no derivable category. This
// is the block condition: the backend rejects such a template (422), so the FE
// must not let the operator submit it.
const hasMissingCategory = computed(
  () => Boolean(selectedTemplate.value) && derivedCategory.value === null
);

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

// Each selected inbox is Cloud-only. When exactly one is selected, link straight
// to its settings Templates tab so the operator can create/manage templates; the
// link is hidden for a multi-inbox selection (no single target to deep-link to).
const manageTemplatesRoute = computed(() => {
  if (selectedInboxIds.value.length !== 1) return null;
  return {
    name: 'settings_inbox_show',
    params: {
      accountId: route.params.accountId,
      inboxId: selectedInboxIds.value[0],
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
  () =>
    v$.value.$invalid ||
    !hasAudience.value ||
    hasMissingCategory.value ||
    isCreating.value
);

// Toggling the inbox SET changes the approved-in-all intersection, so a
// previously-selected template may drop out and its derived category may change.
// Reset the template (and its validation) whenever membership changes.
const toggleInbox = inboxId => {
  if (isInboxSelected(inboxId)) {
    selectedInboxIds.value = selectedInboxIds.value.filter(
      id => id !== inboxId
    );
  } else {
    selectedInboxIds.value = [...selectedInboxIds.value, inboxId];
  }
  v$.value.selectedInboxIds.$touch();
  selectedTemplate.value = '';
  v$.value.selectedTemplate.$reset();
};

const onTemplateChange = () => {
  v$.value.selectedTemplate.$touch();
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
  // GAP A: the submitted (derived) category didn't match the template's real
  // category in every inbox — usually the template was edited/un-approved after
  // selection. Tell the operator to reselect the template.
  if (message === 'template_category_mismatch') {
    return t('DISPARADOR_MGMT.CREATE.API.ERRORS.TEMPLATE_CATEGORY_MISMATCH');
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
      // GAP A: derived from the template, never operator-chosen — matches the
      // backend's real-category validation across all selected inboxes.
      template_category: derivedCategory.value,
      conversation_status: selectedConversationStatus.value,
      // GAP D: send EVERY selected inbox, not a single id.
      inbox_ids: selectedInboxIds.value,
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
  selectedInboxIds.value = [];
  selectedTemplate.value = '';
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
        <div
          v-if="hasCloudInbox"
          class="flex flex-col gap-px rounded-lg outline outline-1 outline-n-weak bg-n-alpha-black2"
        >
          <label
            v-for="inbox in cloudInboxes"
            :key="inbox.id"
            class="flex items-center gap-2 px-3 py-2 cursor-pointer"
          >
            <Checkbox
              :model-value="isInboxSelected(inbox.id)"
              @change="toggleInbox(inbox.id)"
            />
            <span class="text-sm truncate text-n-slate-12">
              {{ inbox.name }}
            </span>
          </label>
        </div>
        <p v-else class="mb-0 text-sm text-n-slate-11">
          {{ t('DISPARADOR_MGMT.CREATE.FORM.INBOX.EMPTY') }}
        </p>
        <p
          v-if="hasCloudInbox && v$.selectedInboxIds.$error"
          class="mb-0 text-sm text-n-ruby-11"
        >
          {{ t('DISPARADOR_MGMT.CREATE.FORM.INBOX.ERROR') }}
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
          v-if="selectedInboxIds.length && templateOptions.length"
          v-model="selectedTemplate"
          class="!w-full [&>select]:w-full"
          :options="templateOptions"
          :placeholder="t('DISPARADOR_MGMT.CREATE.FORM.TEMPLATE.PLACEHOLDER')"
          :error="
            v$.selectedTemplate.$error
              ? t('DISPARADOR_MGMT.CREATE.FORM.TEMPLATE.ERROR')
              : ''
          "
          @update:model-value="onTemplateChange"
        />
        <p
          v-else-if="selectedInboxIds.length"
          class="mb-0 text-sm text-n-slate-11"
        >
          {{ t('DISPARADOR_MGMT.CREATE.FORM.TEMPLATE.EMPTY_INTERSECTION') }}
        </p>
        <p v-else class="mb-0 text-sm text-n-slate-11">
          {{ t('DISPARADOR_MGMT.CREATE.FORM.TEMPLATE.EMPTY') }}
        </p>
      </div>

      <div class="flex flex-col gap-1">
        <span class="text-heading-3 text-n-slate-12">
          {{ t('DISPARADOR_MGMT.CREATE.FORM.CATEGORY.LABEL') }}
        </span>
        <!-- GAP A: read-only derived category. No picker — the operator cannot
             choose a category different from the template's real one. -->
        <span
          v-if="derivedCategoryLabel"
          class="inline-flex items-center self-start px-2 py-0.5 text-xs font-medium rounded-md text-n-slate-12 bg-n-alpha-2"
        >
          {{ derivedCategoryLabel }}
        </span>
        <p v-else-if="hasMissingCategory" class="mb-0 text-sm text-n-ruby-11">
          {{ t('DISPARADOR_MGMT.CREATE.FORM.CATEGORY.MISSING') }}
        </p>
        <p v-else class="mb-0 text-sm text-n-slate-11">
          {{ t('DISPARADOR_MGMT.CREATE.FORM.CATEGORY.DERIVED_HINT') }}
        </p>
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
