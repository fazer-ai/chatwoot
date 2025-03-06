<script setup>
import QrcodeVue from 'qrcode.vue';
import InboxName from '../../../../../components/widgets/InboxName.vue';

const props = defineProps({
  onClose: { type: Function, default: () => {} },
  inbox: {
    type: Object,
    required: true,
  },
});
const emit = defineEmits(['close']);

const show = defineModel('show', { type: Boolean, default: false });
const close = () => {
  show.value = false;
  emit('close');
  props.onClose();
};
</script>

<template>
  <woot-modal v-model:show="show" size="small" :on-close="close">
    <div class="flex flex-col h-auto overflow-auto">
      <woot-modal-header
        :header-title="
          $t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.LINK_DEVICE_MODAL.TITLE')
        "
        :header-content="
          $t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.LINK_DEVICE_MODAL.SUBTITLE')
        "
      />

      <div class="flex flex-col gap-4 p-8 pt-4">
        <InboxName
          :inbox="inbox"
          class="!text-lg self-center"
          with-phone-number
        />

        <QrcodeVue value="qrcode" class="mx-auto" />

        <woot-button class="button clear w-fit" @click="close">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.LINK_DEVICE_MODAL.CLOSE') }}
        </woot-button>
      </div>
    </div>
  </woot-modal>
</template>
