<script setup>
import { onMounted, computed } from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import InboxName from '../../../../../components/widgets/InboxName.vue';
import Spinner from 'shared/components/Spinner.vue';
import { INBOX_CHANNEL_PROVIDER_CONNECTION_STATUS } from 'dashboard/helper/inbox';

const props = defineProps({
  show: { type: Boolean, require: true },
  onClose: { type: Function, required: true },
  inbox: {
    type: Object,
    required: true,
  },
});
const providerConnection = computed(() => props.inbox.provider_connection);
const qrcode = computed(() => providerConnection.value?.qrcode);
const status = computed(() => providerConnection.value?.status);
const setupNeeded = computed(
  () => status.value === INBOX_CHANNEL_PROVIDER_CONNECTION_STATUS.SETUP_NEEDED
);

const store = useStore();
onMounted(() => {
  if (setupNeeded.value) {
    store
      .dispatch('inboxes/setupChannelProviderConnection', props.inbox.id)
      .catch(error => useAlert(error.message));
  }
});
</script>

<template>
  <woot-modal :show="show" size="small" @close="onClose">
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
        <div class="flex flex-col gap-4 items-center">
          <InboxName :inbox="inbox" class="!text-lg" with-phone-number />

          <template v-if="setupNeeded">
            <div v-if="!qrcode" class="flex flex-col gap-4 items-center">
              <p>
                {{
                  $t(
                    'INBOX_MGMT.ADD.WHATSAPP.BAILEYS.LINK_DEVICE_MODAL.LOADING_QRCODE'
                  )
                }}
              </p>
              <Spinner />
            </div>
            <img
              v-if="qrcode"
              :src="qrcode"
              alt="QR Code"
              class="w-[276px] h-[276px]"
            />
          </template>
        </div>

        <woot-button class="button clear w-fit" @click="onClose">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.LINK_DEVICE_MODAL.CLOSE') }}
        </woot-button>
      </div>
    </div>
  </woot-modal>
</template>
