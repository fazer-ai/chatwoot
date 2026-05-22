<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';

const { t } = useI18n();
const store = useStore();

const accountId = useMapGetter('getCurrentAccountId');
const accountGetter = useMapGetter('accounts/getAccount');
const inboxGetter = useMapGetter('inboxes/getInbox');

const account = computed(() => accountGetter.value(accountId.value));
const isTestEnvironment = computed(() => account.value?.environment === 'test');

const simulatorInbox = computed(() =>
  inboxGetter.value(account.value?.simulator_inbox_id)
);

const websiteToken = computed(() => simulatorInbox.value?.website_token || '');

const iframeSrc = computed(() => {
  if (!websiteToken.value) return '';
  return `/simulator?website_token=${encodeURIComponent(websiteToken.value)}`;
});

// The sidebar already pre-fetches inboxes on mount, but this page can be
// opened directly via deep link (it's a `target=_blank` from the badge).
// Re-trigger the fetch defensively so the iframe always has a token to
// build the URL with.
onMounted(() => {
  if (!simulatorInbox.value?.id) {
    store.dispatch('inboxes/get');
  }
});
</script>

<template>
  <div class="flex flex-col w-full h-full bg-n-slate-2">
    <template v-if="!isTestEnvironment">
      <div class="flex items-center justify-center flex-1">
        <EmptyState
          :title="t('SIMULATOR.UNAVAILABLE.TITLE')"
          :message="t('SIMULATOR.UNAVAILABLE.MESSAGE')"
        />
      </div>
    </template>
    <template v-else-if="iframeSrc">
      <iframe
        :src="iframeSrc"
        :title="t('SIMULATOR.PLACEHOLDER.TITLE')"
        class="w-full h-full border-0"
        allow="clipboard-read; clipboard-write"
      />
    </template>
    <template v-else>
      <div class="flex items-center justify-center flex-1">
        <EmptyState
          :title="t('SIMULATOR.PLACEHOLDER.TITLE')"
          :message="t('SIMULATOR.LOADING')"
        />
      </div>
    </template>
  </div>
</template>
