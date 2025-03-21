<script setup>
import { onMounted, computed, onUnmounted, ref, watchEffect } from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import InboxName from 'dashboard/components/widgets/InboxName.vue';
import Spinner from 'shared/components/Spinner.vue';

const props = defineProps({
  show: { type: Boolean, required: true },
  onClose: { type: Function, required: true },
  inbox: {
    type: Object,
    required: true,
  },
});

const loading = ref(false);

const providerConnection = computed(() => props.inbox.provider_connection);
const connection = computed(() => providerConnection.value?.connection);
const qrDataUrl = computed(() => providerConnection.value?.qr_data_url);
const error = computed(() => providerConnection.value?.error);

const store = useStore();

const setup = () => {
  loading.value = true;
  store
    .dispatch('inboxes/setupChannelProvider', props.inbox.id)
    .catch(e => useAlert(e.message));
};
const disconnect = () => {
  loading.value = true;
  store
    .dispatch('inboxes/disconnectChannelProvider', props.inbox.id)
    .catch(e => useAlert(e.message));
};

onMounted(() => {
  if (!connection.value || connection.value === 'close') {
    setup();
  }
});
onUnmounted(() => {
  if (connection.value === 'connecting') {
    disconnect();
  }
});
watchEffect(() => {
  if (connection.value) {
    loading.value = false;
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

          <template v-if="error || connection === 'close'">
            <p v-if="error" class="text-red-500">
              {{ error }}
            </p>
            <woot-button
              class="button clear w-fit"
              :is-loading="loading"
              @click="setup"
            >
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.BAILEYS.LINK_DEVICE_MODAL.LINK_DEVICE'
                )
              }}
            </woot-button>
          </template>
          <template v-else-if="!connection || connection !== 'open'">
            <div v-if="!qrDataUrl" class="flex flex-col gap-4 items-center">
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
              v-else
              :src="qrDataUrl"
              alt="QR Code"
              class="w-[276px] h-[276px]"
            />
          </template>
          <template v-if="connection === 'open'">
            <woot-button
              class="button clear w-fit"
              :is-loading="loading"
              @click="disconnect"
            >
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.BAILEYS.LINK_DEVICE_MODAL.DISCONNECT'
                )
              }}
            </woot-button>
          </template>
        </div>

        <woot-button class="button clear w-fit" @click="onClose">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.LINK_DEVICE_MODAL.CLOSE') }}
        </woot-button>
      </div>
    </div>
  </woot-modal>
</template>
