<script setup>
import { computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import Whatsapp from './channels/Whatsapp.vue';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

const route = useRoute();
const router = useRouter();
const store = useStore();

const inboxId = computed(() => Number(route.params.inboxId));
const inbox = computed(() => store.getters['inboxes/getInbox'](inboxId.value));

const redirectBackIfInvalid = () => {
  if (!inbox.value?.id) return;
  if (inbox.value.channel_type !== INBOX_TYPES.WHATSAPP) {
    router.replace({
      name: 'settings_inbox_show',
      params: { inboxId: inboxId.value },
    });
  }
};

onMounted(() => {
  if (!inbox.value?.id) {
    store.dispatch('inboxes/get');
  }
  redirectBackIfInvalid();
});
</script>

<template>
  <div class="w-full h-full overflow-auto">
    <Whatsapp v-if="inbox?.id" mode="convert" :inbox="inbox" />
  </div>
</template>
