<script setup>
import { computed, nextTick, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// Ticket detail modal used by Meus Tickets. Shows the full ticket data
// as a definition-list style form (ID / Abertura / Problema / Status /
// Atualização Auris / Agente / Link mensagem), plus a compact
// "Incluir mais contexto" section. Any comment submitted from that
// section goes to ClickUp via AddCommentJob — the ops team gets it as
// a comment on the same task the ticket is linked to.

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

const formatDate = timestamp => {
  if (!timestamp) return EMPTY_CELL;
  const date = new Date(timestamp);
  return date.toLocaleDateString(undefined, {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
};

// Deep link that reproduces what the operator would see in the browser
// URL bar. Origin comes from window.location so it stays correct across
// homolog / prod / worktrees without needing FRONTEND_URL wired to the
// bundle.
const messageLink = computed(() => {
  if (!ticket.value?.conversation_display_id || !ticket.value?.message_id) {
    return null;
  }
  const account = accountId.value;
  const conv = ticket.value.conversation_display_id;
  const msg = ticket.value.message_id;
  return `${window.location.origin}/app/accounts/${account}/conversations/${conv}?messageId=${msg}`;
});

// Open the dialog first (mounts the teleported <dialog> element into the
// DOM with an empty slot body), then set the ticket on the next tick.
// Setting ticket before .open() triggers a render pass where the
// v-if="ticket" block wants to mount inside a slot whose parent node
// hasn't been created yet by the Teleport — Vue then throws
// `Cannot read properties of null (reading 'parentNode')` and the slot
// stays empty on screen.
const openWith = fresh => {
  comment.value = '';
  dialogRef.value?.open();
  nextTick(() => {
    ticket.value = fresh;
  });
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
      <!-- Definition-list style grid: label (col 1) / value (col 2) -->
      <dl
        class="grid grid-cols-[max-content_1fr] gap-x-6 gap-y-3 text-sm items-baseline"
      >
        <dt class="text-xs uppercase text-n-slate-11 whitespace-nowrap">
          {{ t('MEUS_TICKETS.DETAIL.ID') }}
        </dt>
        <dd class="text-n-slate-12 font-medium">
          {{ ticket.display_id }}
        </dd>

        <dt class="text-xs uppercase text-n-slate-11 whitespace-nowrap">
          {{ t('MEUS_TICKETS.DETAIL.OPENED_AT') }}
        </dt>
        <dd class="text-n-slate-12">
          {{ formatDate(ticket.created_at) }}
        </dd>

        <dt
          class="text-xs uppercase text-n-slate-11 whitespace-nowrap self-start pt-0.5"
        >
          {{ t('MEUS_TICKETS.DETAIL.PROBLEM') }}
        </dt>
        <dd class="text-n-slate-12 whitespace-pre-wrap">
          {{ ticket.relatar_problema }}
        </dd>

        <template v-if="ticket.comportamento_esperado">
          <dt
            class="text-xs uppercase text-n-slate-11 whitespace-nowrap self-start pt-0.5"
          >
            {{ t('MEUS_TICKETS.DETAIL.EXPECTED') }}
          </dt>
          <dd class="text-n-slate-12 whitespace-pre-wrap">
            {{ ticket.comportamento_esperado }}
          </dd>
        </template>

        <dt class="text-xs uppercase text-n-slate-11 whitespace-nowrap">
          {{ t('MEUS_TICKETS.DETAIL.STATUS') }}
        </dt>
        <dd class="text-n-slate-12">
          {{
            ticket.clickup_status_name || t('MEUS_TICKETS.STATUS.PENDING_SYNC')
          }}
        </dd>

        <dt
          class="text-xs uppercase text-n-slate-11 whitespace-nowrap self-start pt-0.5"
        >
          {{ t('MEUS_TICKETS.DETAIL.RESPONSE') }}
        </dt>
        <dd>
          <div
            v-if="ticket.resposta_para_cliente"
            class="text-n-slate-12 whitespace-pre-wrap bg-n-teal-2 border border-n-teal-6 rounded-lg p-3"
          >
            {{ ticket.resposta_para_cliente }}
          </div>
          <span v-else class="text-n-slate-10">{{ EMPTY_CELL }}</span>
        </dd>

        <dt class="text-xs uppercase text-n-slate-11 whitespace-nowrap">
          {{ t('MEUS_TICKETS.DETAIL.AGENT') }}
        </dt>
        <dd class="text-n-slate-12">
          {{ ticket.user?.name || EMPTY_CELL }}
        </dd>

        <dt class="text-xs uppercase text-n-slate-11 whitespace-nowrap">
          {{ t('MEUS_TICKETS.DETAIL.MESSAGE_LINK') }}
        </dt>
        <dd>
          <a
            v-if="messageLink"
            :href="messageLink"
            class="text-n-brand hover:underline break-all text-sm"
            @click.prevent="goToMessage"
          >
            {{ messageLink }}
          </a>
          <span v-else class="text-n-slate-10">{{ EMPTY_CELL }}</span>
        </dd>
      </dl>

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

      <div v-if="ticket.clickup_task_url" class="flex flex-wrap gap-2">
        <Button
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
