<script setup>
import { ref, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const { t } = useI18n();

const dialogRef = ref(null);
const agentName = ref('');

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
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="$t('CONVERSATION.ASSIGNMENT_CONFLICT.TITLE')"
    :description="
      agentName
        ? t('CONVERSATION.ASSIGNMENT_CONFLICT.DESCRIPTION', { agentName })
        : t('CONVERSATION.ASSIGNMENT_CONFLICT.DESCRIPTION_UNKNOWN_AGENT')
    "
    :confirm-button-label="$t('CONVERSATION.ASSIGNMENT_CONFLICT.CONFIRM')"
    :show-cancel-button="false"
    width="sm"
    @confirm="dialogRef?.close()"
  />
</template>
