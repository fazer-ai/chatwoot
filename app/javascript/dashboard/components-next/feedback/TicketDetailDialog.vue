<script setup>
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// Ticket detail modal used by Meus Tickets. Shows the readonly ticket
// captured at open time (id, status, agent, problem, expected behavior,
// resposta from ops) plus a compact "Incluir mais contexto" section
// that posts a comment on the ClickUp task via AddCommentJob.

const { t } = useI18n();
const store = useStore();
const router = useRouter();

const accountId = useMapGetter('getCurrentAccountId');
const currentRole = useMapGetter('getCurrentRole');
const uiFlags = useMapGetter('tickets/getUIFlags');

const ticket = ref(null);
const dialogRef = ref(null);
const comment = ref('');
const EMPTY_CELL = '—';

// Prefix the ticket id on the dialog title so the operator can mention
// it back to the ops team over chat / phone without having to hunt for
// it in the row.
const dialogTitle = computed(() => {
  const base = t('MEUS_TICKETS.DETAIL.TITLE');
  return ticket.value?.display_id
    ? `#${ticket.value.display_id} — ${base}`
    : base;
});

const isSyncPending = computed(
  () => ticket.value?.sync_status === 'pending_sync'
);
const isSyncFailed = computed(
  () => ticket.value?.sync_status === 'sync_failed'
);
// Only administrators see the ClickUp shortcut — it exposes ops-side
// internals (task id, workspace URL) that don't belong in front of the
// operator or the manager.
const isAdministrator = computed(() => currentRole.value === 'administrator');
// Agent → their own tickets (backend policy enforces this).
// Manager, Administrator → any ticket in the account.
// The `sync_synced` guard is on top: without a ClickUp task id the
// comment has nowhere to land, so the affordance stays hidden.
const canComment = computed(() => {
  const role = currentRole.value;
  const roleAllowed = ['agent', 'manager', 'administrator'].includes(role);
  return (
    roleAllowed &&
    ticket.value?.sync_status === 'synced' &&
    !!ticket.value?.clickup_task_id
  );
});

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
  if (!ticket.value?.conversation_display_id || !ticket.value?.message_id) {
    return;
  }
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: accountId.value,
      conversation_id: ticket.value.conversation_display_id,
    },
    query: { messageId: String(ticket.value.message_id) },
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
    :title="dialogTitle"
    :description="t('MEUS_TICKETS.DETAIL.SUBTITLE')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="handleClose"
  >
    <div v-if="ticket" class="flex flex-col gap-5">
      <!-- Header row: ID, Status, Agente in a compact 2-col grid.
           Same visual style as the previous release; ID added inline. -->
      <div class="grid grid-cols-2 gap-4 text-sm">
        <div>
          <p class="text-xs uppercase text-n-slate-11 mb-1">
            {{ t('MEUS_TICKETS.DETAIL.ID') }}
          </p>
          <p class="text-n-slate-12 font-medium">
            {{ ticket.display_id }}
          </p>
        </div>
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
          v-if="isAdministrator && ticket.clickup_task_url"
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
            color="blue"
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
