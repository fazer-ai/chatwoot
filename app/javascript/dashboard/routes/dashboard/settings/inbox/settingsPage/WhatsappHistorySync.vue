<script setup>
import { computed, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { hasCapability, CAPABILITIES } from 'dashboard/helper/whatsappSession';

import SettingsSection from 'dashboard/components/SettingsSection.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

// Standing consent: on every pairing, keep the archive the phone offers.
//
// An inbox-level setting because that is the scope of the decision -- it is answered once
// for the whole inbox and applies to every chat the phone hands over. Asking for one
// thread's older messages is a different act, taken by whoever is reading that thread, and
// it lives at the top of the thread rather than here.
//
// Shared by every provider that can do it, session and legacy alike, and gated on the
// capability rather than on the provider name.
const props = defineProps({
  inbox: { type: Object, required: true },
});

const store = useStore();
const { t } = useI18n();

const supported = computed(() =>
  hasCapability(props.inbox, CAPABILITIES.HISTORY_SYNC)
);

// Kept apart from the inbox so a failed save leaves the switch showing what the server
// still holds.
const enabled = ref(false);
watch(
  () => props.inbox.provider_config,
  config => {
    enabled.value = Boolean(config?.history_sync);
  },
  { immediate: true }
);

const saveSetting = async () => {
  try {
    await store.dispatch('inboxes/updateInbox', {
      id: props.inbox.id,
      formData: false,
      channel: {
        provider_config: {
          ...props.inbox.provider_config,
          history_sync: enabled.value,
        },
      },
    });
    useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
    // The switch has already moved by the time this runs, and the next change event needs
    // a different value, so leaving it there would mean toggling away and back to retry.
    enabled.value = Boolean(props.inbox.provider_config?.history_sync);
  }
};
</script>

<template>
  <div v-if="supported">
    <SettingsSection
      :title="$t('INBOX_MGMT.ADD.WHATSAPP.SESSION.FIELDS.HISTORY_SYNC.LABEL')"
      :sub-title="
        $t('INBOX_MGMT.ADD.WHATSAPP.SESSION.FIELDS.HISTORY_SYNC.DESCRIPTION')
      "
    >
      <div class="flex items-center gap-2">
        <Switch id="history_sync" v-model="enabled" @change="saveSetting" />
        <span class="text-sm">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.SESSION.FIELDS.HISTORY_SYNC.LABEL') }}
        </span>
      </div>
    </SettingsSection>
  </div>
</template>
