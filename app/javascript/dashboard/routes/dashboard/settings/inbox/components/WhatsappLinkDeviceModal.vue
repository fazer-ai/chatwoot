<script setup>
import { onMounted, computed, onUnmounted, ref, watchEffect } from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import InboxName from 'dashboard/components/widgets/InboxName.vue';
import Spinner from 'shared/components/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  show: { type: Boolean, required: true },
  onClose: { type: Function, required: true },
  isSetup: { type: Boolean, required: false },
  inbox: {
    type: Object,
    required: true,
  },
});

const store = useStore();

const providerConnection = computed(() => props.inbox.provider_connection);
const connection = computed(() => providerConnection.value?.connection);
const qrDataUrl = computed(() => providerConnection.value?.qr_data_url);
const error = computed(() => providerConnection.value?.error);

// Alternative onboarding when WhatsApp's extra device-linking verification blocks
// the QR: install the browser extension and import an already-linked session.
const extensionUrl =
  'https://chromewebstore.google.com/detail/fazerai-whatsapp-connecto/nchdjpjplcnggifnemiiclgjplooible';

const loading = ref(false);
const showImportDetails = ref(false);

const handleError = e => {
  useAlert(e.message);
  loading.value = false;
};
const setup = () => {
  loading.value = true;
  store
    .dispatch('inboxes/setupChannelProvider', props.inbox.id)
    .catch(handleError);
};
const disconnect = () => {
  loading.value = true;
  store
    .dispatch('inboxes/disconnectChannelProvider', props.inbox.id)
    .catch(handleError);
};

onMounted(() => {
  if (!connection.value || connection.value === 'close') {
    setup();
  }
});
onUnmounted(() => {
  if (
    connection.value === 'connecting' ||
    connection.value === 'reconnecting'
  ) {
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
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.TITLE'
          )
        "
        :header-content="
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.SUBTITLE'
          )
        "
      />

      <div class="flex flex-col gap-4 p-8 pt-4">
        <div class="flex flex-col gap-4 items-center">
          <InboxName
            :inbox="inbox"
            class="!text-lg"
            with-phone-number
            with-provider-connection-status
          />

          <template v-if="!connection || connection === 'close' || error">
            <p v-if="error" class="text-red-500 text-center">
              {{ error }}
            </p>
            <Button :is-loading="loading" @click="setup">
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.LINK_DEVICE'
                )
              }}
            </Button>
          </template>

          <template v-else-if="connection === 'connecting'">
            <div v-if="!qrDataUrl" class="flex flex-col gap-4 items-center">
              <p>
                {{
                  $t(
                    'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.LOADING_QRCODE'
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

          <template v-else-if="connection === 'reconnecting'">
            <p>
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.RECONNECTING'
                )
              }}
            </p>
            <Spinner />
          </template>

          <template v-else-if="connection === 'open'">
            <p v-if="isSetup" class="text-center">
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.CONNECTED'
                )
              }}
            </p>
            <div class="flex gap-2">
              <Button ghost :is-loading="loading" @click="disconnect">
                {{
                  $t(
                    'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.DISCONNECT'
                  )
                }}
              </Button>
              <router-link
                v-if="isSetup"
                :to="{
                  name: 'inbox_dashboard',
                  params: { inboxId: inbox.id },
                }"
              >
                <Button
                  solid
                  teal
                  :label="$t('INBOX_MGMT.FINISH.BUTTON_TEXT')"
                />
              </router-link>
            </div>
          </template>

          <!-- Fallback kept available in every non-open state, including while the
               QR is shown: import an already-linked session via the extension. -->
          <div
            v-if="connection !== 'open'"
            class="flex flex-col gap-1 items-center pt-4 mt-2 w-full border-t border-n-weak"
          >
            <p class="text-sm font-medium text-center text-n-slate-12">
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.IMPORT_SESSION_TITLE'
                )
              }}
            </p>
            <button
              v-if="!showImportDetails"
              type="button"
              :aria-expanded="showImportDetails"
              class="text-xs underline text-n-slate-11 hover:text-n-slate-12"
              @click="showImportDetails = true"
            >
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.IMPORT_SESSION_SHOW_MORE'
                )
              }}
            </button>
            <template v-else>
              <p class="text-sm text-center text-n-slate-11">
                {{
                  $t(
                    'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.IMPORT_SESSION_DESC'
                  )
                }}
              </p>
              <a :href="extensionUrl" target="_blank" rel="noopener noreferrer">
                <Button
                  link
                  blue
                  :label="
                    $t(
                      'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.IMPORT_SESSION_INSTALL'
                    )
                  "
                />
              </a>
            </template>
          </div>
        </div>
      </div>
    </div>
  </woot-modal>
</template>
