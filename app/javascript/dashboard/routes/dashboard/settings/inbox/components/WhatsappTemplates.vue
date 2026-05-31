<script setup>
import { computed, ref } from 'vue';
import { format } from 'date-fns';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

import ButtonV4 from 'next/button/Button.vue';
import BaseTable from 'dashboard/components-next/table/BaseTable.vue';
import BaseTableRow from 'dashboard/components-next/table/BaseTableRow.vue';
import BaseTableCell from 'dashboard/components-next/table/BaseTableCell.vue';
import SubmitTemplateDialog from './SubmitTemplateDialog.vue';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
});

const store = useStore();
const { t } = useI18n();

const uiFlags = useMapGetter('inboxes/getUIFlags');
const isSyncing = computed(() => uiFlags.value.isSyncingTemplates);

const submitDialogRef = ref(null);

// Submit is a Meta-only write that requires WhatsApp Cloud; non-Cloud WhatsApp
// inboxes share this tab but would 422 on submit, so gate the action.
const isCloudInbox = computed(() => props.inbox.provider === 'whatsapp_cloud');

// The Meta WRITE (submit) is gated behind its own installation flag (default OFF).
// When off, hide the submit affordance entirely; the read-only sync stays available.
const isWhatsappTemplateSubmitEnabled = useMapGetter(
  'globalConfig/isWhatsappTemplateSubmitEnabled'
);
const canSubmitTemplate = computed(
  () => isCloudInbox.value && isWhatsappTemplateSubmitEnabled.value
);

const openSubmitDialog = () => submitDialogRef.value?.open();

const STATUS_COLORS = {
  approved: 'text-n-teal-11',
  pending: 'text-n-amber-11',
  rejected: 'text-n-ruby-9',
};

const STATUS_LABEL_KEYS = {
  approved: 'INBOX_MGMT.WHATSAPP_TEMPLATES.STATUS.APPROVED',
  pending: 'INBOX_MGMT.WHATSAPP_TEMPLATES.STATUS.PENDING',
  rejected: 'INBOX_MGMT.WHATSAPP_TEMPLATES.STATUS.REJECTED',
};

const templates = computed(() => {
  const list = props.inbox.message_templates;
  return Array.isArray(list) ? list : [];
});

const lastSyncedAt = computed(() => {
  const value = props.inbox.message_templates_last_updated;
  if (!value) return '';
  return format(new Date(value), 'MMM d, yyyy h:mm a');
});

const tableHeaders = computed(() => [
  t('INBOX_MGMT.WHATSAPP_TEMPLATES.TABLE.NAME'),
  t('INBOX_MGMT.WHATSAPP_TEMPLATES.TABLE.STATUS'),
  t('INBOX_MGMT.WHATSAPP_TEMPLATES.TABLE.CATEGORY'),
  t('INBOX_MGMT.WHATSAPP_TEMPLATES.TABLE.LANGUAGE'),
]);

const normalizedStatus = status => (status || '').toLowerCase();

const getStatusTextColor = status =>
  STATUS_COLORS[normalizedStatus(status)] || 'text-n-slate-12';

const formatStatusLabel = status => {
  const labelKey = STATUS_LABEL_KEYS[normalizedStatus(status)];
  if (labelKey) {
    return t(labelKey);
  }
  return status || t('INBOX_MGMT.WHATSAPP_TEMPLATES.STATUS.UNKNOWN');
};

const handleSync = async () => {
  try {
    await store.dispatch('inboxes/syncTemplates', props.inbox.id);
    useAlert(t('INBOX_MGMT.WHATSAPP_TEMPLATES.SYNC.SUCCESS'));
  } catch (error) {
    useAlert(t('INBOX_MGMT.WHATSAPP_TEMPLATES.SYNC.ERROR'));
  }
};
</script>

<template>
  <div class="gap-4 mx-6">
    <div
      class="px-5 py-5 space-y-6 rounded-xl outline outline-1 -outline-offset-1 outline-n-weak bg-n-solid-2"
    >
      <div
        class="flex flex-col gap-5 justify-between items-start w-full md:flex-row"
      >
        <div>
          <span class="text-heading-3 text-n-slate-12">
            {{ t('INBOX_MGMT.WHATSAPP_TEMPLATES.TITLE') }}
          </span>
          <p class="mt-1 text-body-main text-n-slate-11">
            {{ t('INBOX_MGMT.WHATSAPP_TEMPLATES.DESCRIPTION') }}
          </p>
          <p v-if="lastSyncedAt" class="mt-1 text-label text-n-slate-11">
            {{
              t('INBOX_MGMT.WHATSAPP_TEMPLATES.LAST_SYNCED', {
                time: lastSyncedAt,
              })
            }}
          </p>
        </div>
        <div class="flex flex-shrink-0 gap-2">
          <ButtonV4
            v-if="canSubmitTemplate"
            sm
            faded
            slate
            icon="i-lucide-plus"
            @click="openSubmitDialog"
          >
            {{ t('INBOX_MGMT.WHATSAPP_TEMPLATES.NEW_BUTTON') }}
          </ButtonV4>
          <ButtonV4
            sm
            solid
            blue
            :loading="isSyncing"
            :disabled="isSyncing"
            @click="handleSync"
          >
            {{ t('INBOX_MGMT.WHATSAPP_TEMPLATES.SYNC.BUTTON') }}
          </ButtonV4>
        </div>
      </div>

      <SubmitTemplateDialog
        v-if="canSubmitTemplate"
        ref="submitDialogRef"
        :inbox-id="inbox.id"
      />

      <BaseTable
        :headers="tableHeaders"
        :items="templates"
        :no-data-message="t('INBOX_MGMT.WHATSAPP_TEMPLATES.EMPTY')"
      >
        <template #row="{ items }">
          <BaseTableRow
            v-for="(template, index) in items"
            :key="`${template.id || template.name}-${index}`"
            :item="template"
          >
            <template #default>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-12">
                  {{ template.name }}
                </span>
              </BaseTableCell>

              <BaseTableCell>
                <span
                  class="inline-flex items-center px-2 py-0.5 min-h-6 text-label-small rounded-md bg-n-alpha-2"
                  :class="getStatusTextColor(template.status)"
                >
                  {{ formatStatusLabel(template.status) }}
                </span>
              </BaseTableCell>

              <BaseTableCell>
                <span class="text-body-main text-n-slate-11">
                  {{ template.category || '—' }}
                </span>
              </BaseTableCell>

              <BaseTableCell>
                <span class="text-body-main text-n-slate-11">
                  {{ template.language || '—' }}
                </span>
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>
    </div>
  </div>
</template>
