<script setup>
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// Ticket detail modal used by Meus Tickets. Shows the readonly ticket
// captured at open time (problem, expected, status, ClickUp URL, response
// from ops) plus a compact "add comment" input. Deep-links the operator
// back to the exact message that triggered the ticket.

const { t } = useI18n();
const store = useStore();
const router = useRouter();

const accountId = useMapGetter('getCurrentAccountId');
const uiFlags = useMapGetter('tickets/getUIFlags');

const ticket = ref(null);
const dialogRef = ref(null);
const comment = ref('');
const EMPTY_CELL = '—';

const isSyncPending = computed(
  () => ticket.value?.sync_status === 'pending_sync'
);
const isSyncFailed = computed(
  () => ticket.value?.sync_status === 'sync_failed'
);
const canComment = computed(
  () =>
    ticket.value?.sync_status === 'synced' && !!ticket.value?.clickup_task_id
);

const openWith = fresh => {
  ticket.value = fresh;
  comment.value = '';
  dialogRef.value?.open();
};

const handleClose = () => {
  ticket.value = null;
  comment.value = '';
};

const goToMessage = () => {
  if (!ticket.value?.conversation_display_id || !ticket.value?.message_id)
    return;
  const query = { messageId: String(ticket.value.message_id) };
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: accountId.value,
      conversation_id: ticket.value.conversation_display_id,
    },
    query,
  });
  dialogRef.value?.close();
};

const submitComment = async () => {
  if (!comment.value.trim() || !ticket.value?.id) return;
  try {
    await store.dispatch('tickets/addComment', {
      id: ticket.value.id,
      comment: comment.value.trim(),
    });
    useAlert(t('MEUS_TICKETS.DETAIL.COMMENT_SUCCESS'));
    comment.value = '';
  } catch (error) {
    useAlert(error?.message || t('MEUS_TICKETS.DETAIL.COMMENT_ERROR'));
  }
};

defineExpose({ openWith });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="xl"
    :title="t('MEUS_TICKETS.DETAIL.TITLE')"
    :description="t('MEUS_TICKETS.DETAIL.SUBTITLE')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="handleClose"
  >
    <div v-if="ticket" class="flex flex-col gap-5">
      <div class="grid grid-cols-2 gap-4 text-sm">
        <div>
          <p class="text-xs uppercase text-n-slate-11 mb-1">
            {{ t('MEUS_TICKETS.DETAIL.STATUS') }}
          </p>
          <p class="text-n-slate-12">
            {{
              ticket.clickup_status_name ||
              t('MEUS_TICKETS.STATUS.PENDING_SYNC')
            }}
          </p>
        </div>
        <div>
          <p class="text-xs uppercase text-n-slate-11 mb-1">
            {{ t('MEUS_TICKETS.DETAIL.AGENT') }}
          </p>
          <p class="text-n-slate-12">
            {{ ticket.user?.name || EMPTY_CELL }}
          </p>
        </div>
      </div>

      <div>
        <p class="text-xs uppercase text-n-slate-11 mb-1">
          {{ t('MEUS_TICKETS.DETAIL.PROBLEM') }}
        </p>
        <p class="text-sm text-n-slate-12 whitespace-pre-wrap">
          {{ ticket.relatar_problema }}
        </p>
      </div>

      <div v-if="ticket.comportamento_esperado">
        <p class="text-xs uppercase text-n-slate-11 mb-1">
          {{ t('MEUS_TICKETS.DETAIL.EXPECTED') }}
        </p>
        <p class="text-sm text-n-slate-12 whitespace-pre-wrap">
          {{ ticket.comportamento_esperado }}
        </p>
      </div>

      <div v-if="ticket.resposta_para_cliente">
        <p class="text-xs uppercase text-n-slate-11 mb-1">
          {{ t('MEUS_TICKETS.DETAIL.RESPONSE') }}
        </p>
        <div
          class="text-sm text-n-slate-12 whitespace-pre-wrap bg-n-teal-2 border border-n-teal-6 rounded-lg p-3"
        >
          {{ ticket.resposta_para_cliente }}
        </div>
      </div>

      <div
        v-if="isSyncPending"
        class="text-xs text-n-amber-11 bg-n-amber-2 border border-n-amber-6 rounded-lg p-3"
      >
        {{ t('MEUS_TICKETS.DETAIL.PENDING_SYNC') }}
      </div>

      <div
        v-if="isSyncFailed"
        class="text-xs text-n-ruby-11 bg-n-ruby-2 border border-n-ruby-6 rounded-lg p-3"
      >
        {{ t('MEUS_TICKETS.DETAIL.SYNC_FAILED') }}
        <span v-if="ticket.sync_error" class="block mt-1 text-n-slate-11">
          {{ ticket.sync_error }}
        </span>
      </div>

      <div class="flex flex-wrap gap-2">
        <Button
          v-if="ticket.message_id && ticket.conversation_display_id"
          type="button"
          variant="faded"
          color="slate"
          size="sm"
          icon="i-lucide-arrow-up-right"
          :label="t('MEUS_TICKETS.DETAIL.GO_TO_MESSAGE')"
          @click="goToMessage"
        />
        <Button
          v-if="ticket.clickup_task_url"
          type="button"
          variant="faded"
          color="slate"
          size="sm"
          icon="i-lucide-external-link"
          :label="t('MEUS_TICKETS.DETAIL.OPEN_IN_CLICKUP')"
          @click="() => window.open(ticket.clickup_task_url, '_blank')"
        />
      </div>

      <div
        v-if="canComment"
        class="flex flex-col gap-2 border-t border-n-weak pt-4"
      >
        <label
          for="ticket-add-comment"
          class="text-xs uppercase text-n-slate-11"
        >
          {{ t('MEUS_TICKETS.DETAIL.ADD_COMMENT_LABEL') }}
        </label>
        <textarea
          id="ticket-add-comment"
          v-model="comment"
          rows="3"
          :placeholder="t('MEUS_TICKETS.DETAIL.ADD_COMMENT_PLACEHOLDER')"
          class="w-full text-sm rounded-lg border border-n-slate-6 bg-n-alpha-black1 focus:outline-none focus:border-n-brand p-3 resize-y text-n-slate-12"
        />
        <div class="flex justify-end">
          <Button
            type="button"
            variant="solid"
            color="brand"
            size="sm"
            :is-loading="uiFlags.addingComment"
            :disabled="!comment.trim() || uiFlags.addingComment"
            :label="t('MEUS_TICKETS.DETAIL.ADD_COMMENT_SUBMIT')"
            @click="submitComment"
          />
        </div>
      </div>
    </div>
  </Dialog>
</template>
