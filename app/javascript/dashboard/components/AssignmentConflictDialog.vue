<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();

const dialogRef = ref(null);
const agentName = ref('');

const description = computed(() =>
  agentName.value
    ? t('CONVERSATION.ASSIGNMENT_CONFLICT.DESCRIPTION', {
        agentName: agentName.value,
      })
    : t('CONVERSATION.ASSIGNMENT_CONFLICT.DESCRIPTION_UNKNOWN_AGENT')
);

// Mounted once globally, next to the toast container, because the assignment
// actions that can collide live in four unrelated components (conversation
// sidebar, reply box banner, command bar and the chat list context menu).
const onAssignmentConflict = payload => {
  agentName.value = payload?.agentName || '';
  dialogRef.value?.open();
};

onMounted(() =>
  emitter.on(BUS_EVENTS.ASSIGNMENT_CONFLICT, onAssignmentConflict)
);
onUnmounted(() =>
  emitter.off(BUS_EVENTS.ASSIGNMENT_CONFLICT, onAssignmentConflict)
);
</script>

<template>
  <!-- Title and body live in the default slot rather than in the `title` and
  `description` props so the icon can sit beside them, and so the dialog does
  not render an empty content area between the text and the button. -->
  <Dialog
    ref="dialogRef"
    :show-cancel-button="false"
    :show-confirm-button="false"
    width="sm"
    @confirm="dialogRef?.close()"
  >
    <div class="flex items-start gap-4">
      <div
        class="flex items-center justify-center flex-shrink-0 size-10 rounded-xl bg-n-amber-3"
      >
        <span class="i-lucide-lock text-xl text-n-amber-11" />
      </div>
      <div class="flex flex-col gap-1">
        <h3 class="text-base font-medium leading-6 text-n-slate-12">
          {{ $t('CONVERSATION.ASSIGNMENT_CONFLICT.TITLE') }}
        </h3>
        <p class="mb-0 text-sm text-n-slate-11">
          {{ description }}
        </p>
      </div>
    </div>
    <template #footer>
      <div class="flex justify-end w-full">
        <NextButton
          type="submit"
          :label="$t('CONVERSATION.ASSIGNMENT_CONFLICT.CONFIRM')"
        />
      </div>
    </template>
  </Dialog>
</template>
