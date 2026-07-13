<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// PR2 of the Feedback Tickets project. Operators hit the flag icon next to
// an outgoing/AI message and this dialog collects:
//   - relatar_problema  (required) — what went wrong from their POV
//   - comportamento_esperado (optional) — what should have happened
//   - attachments (optional) — screenshots / evidence, up to 5 files 5MB each
// The dispatch fires POST /tickets which enqueues the ClickUp sync + the
// attachment jobs. Attachments upload asynchronously behind the ticket, so
// the operator does not have to wait for the ClickUp side to confirm.

const MAX_ATTACHMENTS = 5;
const MAX_FILE_SIZE_BYTES = 5 * 1024 * 1024;
const requiredMark = '*';

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const fileInputRef = ref(null);

const messageId = ref(null);
const conversationId = ref(null); // eslint-disable-line no-unused-vars

const relatarProblema = ref('');
const comportamentoEsperado = ref('');
const attachments = ref([]);
const attachmentError = ref('');

const uiFlags = computed(() => store.getters['tickets/getUIFlags'] || {});
const isSubmitting = computed(() => uiFlags.value.creatingItem);
const canSubmit = computed(
  () =>
    relatarProblema.value.trim().length > 0 &&
    comportamentoEsperado.value.trim().length > 0 &&
    !isSubmitting.value
);

const resetForm = () => {
  relatarProblema.value = '';
  comportamentoEsperado.value = '';
  attachments.value = [];
  attachmentError.value = '';
  if (fileInputRef.value) fileInputRef.value.value = '';
};

const handleOpen = payload => {
  messageId.value = payload?.messageId ?? null;
  conversationId.value = payload?.conversationId ?? null;
  resetForm();
  dialogRef.value?.open();
};

const handleClose = () => {
  messageId.value = null;
  conversationId.value = null;
  resetForm();
};

const handleFileChange = event => {
  const picked = Array.from(event.target?.files || []);
  const combined = [...attachments.value, ...picked];

  if (combined.length > MAX_ATTACHMENTS) {
    attachmentError.value = t(
      'CONVERSATION.FEEDBACK_TICKET.ERRORS.TOO_MANY_ATTACHMENTS',
      { max: MAX_ATTACHMENTS }
    );
    event.target.value = '';
    return;
  }

  const oversize = combined.find(file => file.size > MAX_FILE_SIZE_BYTES);
  if (oversize) {
    attachmentError.value = t(
      'CONVERSATION.FEEDBACK_TICKET.ERRORS.FILE_TOO_LARGE',
      { name: oversize.name }
    );
    event.target.value = '';
    return;
  }

  attachmentError.value = '';
  attachments.value = combined;
  event.target.value = '';
};

const removeAttachment = index => {
  const next = [...attachments.value];
  next.splice(index, 1);
  attachments.value = next;
};

const handleSubmit = async () => {
  if (!canSubmit.value || !messageId.value) return;

  try {
    await store.dispatch('tickets/create', {
      messageId: messageId.value,
      relatarProblema: relatarProblema.value.trim(),
      comportamentoEsperado: comportamentoEsperado.value.trim(),
      attachments: attachments.value,
    });
    useAlert(t('CONVERSATION.FEEDBACK_TICKET.SUCCESS'));
    dialogRef.value?.close();
  } catch (error) {
    useAlert(
      error?.message || t('CONVERSATION.FEEDBACK_TICKET.ERRORS.GENERIC')
    );
  }
};

onMounted(() => emitter.on(BUS_EVENTS.OPEN_FEEDBACK_TICKET, handleOpen));
onUnmounted(() => emitter.off(BUS_EVENTS.OPEN_FEEDBACK_TICKET, handleOpen));
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="lg"
    :title="t('CONVERSATION.FEEDBACK_TICKET.TITLE')"
    :description="t('CONVERSATION.FEEDBACK_TICKET.SUBTITLE')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="handleClose"
  >
    <form class="flex flex-col gap-4" @submit.prevent="handleSubmit">
      <div class="flex flex-col gap-1">
        <label
          for="feedback-relatar-problema"
          class="text-sm font-medium text-n-slate-12"
        >
          {{
            `${t('CONVERSATION.FEEDBACK_TICKET.RELATAR_PROBLEMA_LABEL')} ${requiredMark}`
          }}
        </label>
        <textarea
          id="feedback-relatar-problema"
          v-model="relatarProblema"
          rows="4"
          :placeholder="
            t('CONVERSATION.FEEDBACK_TICKET.RELATAR_PROBLEMA_PLACEHOLDER')
          "
          class="w-full text-sm rounded-lg border border-n-slate-6 bg-n-alpha-black1 focus:outline-none focus:border-n-brand p-3 resize-y text-n-slate-12"
          required
        />
      </div>

      <div class="flex flex-col gap-1">
        <label
          for="feedback-comportamento-esperado"
          class="text-sm font-medium text-n-slate-12"
        >
          {{
            `${t('CONVERSATION.FEEDBACK_TICKET.COMPORTAMENTO_ESPERADO_LABEL')} ${requiredMark}`
          }}
        </label>
        <textarea
          id="feedback-comportamento-esperado"
          v-model="comportamentoEsperado"
          rows="3"
          :placeholder="
            t('CONVERSATION.FEEDBACK_TICKET.COMPORTAMENTO_ESPERADO_PLACEHOLDER')
          "
          class="w-full text-sm rounded-lg border border-n-slate-6 bg-n-alpha-black1 focus:outline-none focus:border-n-brand p-3 resize-y text-n-slate-12"
        />
      </div>

      <div class="flex flex-col gap-2">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CONVERSATION.FEEDBACK_TICKET.ATTACHMENTS_LABEL') }}
        </label>
        <div class="flex items-center gap-2">
          <input
            ref="fileInputRef"
            type="file"
            multiple
            class="hidden"
            @change="handleFileChange"
          />
          <Button
            type="button"
            variant="faded"
            color="slate"
            size="sm"
            icon="i-lucide-paperclip"
            :label="t('CONVERSATION.FEEDBACK_TICKET.ATTACHMENTS_PICK')"
            @click="fileInputRef?.click()"
          />
          <span class="text-xs text-n-slate-10">
            {{ t('CONVERSATION.FEEDBACK_TICKET.ATTACHMENTS_HINT') }}
          </span>
        </div>
        <p v-if="attachmentError" class="text-xs text-n-ruby-11">
          {{ attachmentError }}
        </p>
        <ul v-if="attachments.length" class="flex flex-col gap-1">
          <li
            v-for="(file, index) in attachments"
            :key="`${file.name}-${index}`"
            class="flex items-center justify-between text-xs bg-n-slate-2 rounded-md px-2 py-1"
          >
            <span class="truncate text-n-slate-12">{{ file.name }}</span>
            <button
              type="button"
              class="text-n-slate-10 hover:text-n-ruby-11"
              :aria-label="t('CONVERSATION.FEEDBACK_TICKET.ATTACHMENTS_REMOVE')"
              @click="removeAttachment(index)"
            >
              <i class="i-lucide-x size-4" />
            </button>
          </li>
        </ul>
      </div>

      <div class="flex justify-end gap-2 pt-2">
        <Button
          type="button"
          variant="faded"
          color="slate"
          size="sm"
          :label="t('CONVERSATION.FEEDBACK_TICKET.CANCEL')"
          @click="dialogRef?.close()"
        />
        <Button
          type="submit"
          variant="solid"
          color="blue"
          size="sm"
          :is-loading="isSubmitting"
          :disabled="!canSubmit"
          :label="t('CONVERSATION.FEEDBACK_TICKET.SUBMIT')"
        />
      </div>
    </form>
  </Dialog>
</template>
