<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';

const { t } = useI18n();

const accountId = useMapGetter('getCurrentAccountId');
const accountGetter = useMapGetter('accounts/getAccount');
const account = computed(() => accountGetter.value(accountId.value));

const isTestEnvironment = computed(() => account.value?.environment === 'test');
</script>

<template>
  <div class="flex items-center justify-center w-full h-full bg-n-slate-2">
    <EmptyState
      v-if="isTestEnvironment"
      :title="t('SIMULATOR.PLACEHOLDER.TITLE')"
      :message="t('SIMULATOR.PLACEHOLDER.MESSAGE')"
    />
    <EmptyState
      v-else
      :title="t('SIMULATOR.UNAVAILABLE.TITLE')"
      :message="t('SIMULATOR.UNAVAILABLE.MESSAGE')"
    />
  </div>
</template>
