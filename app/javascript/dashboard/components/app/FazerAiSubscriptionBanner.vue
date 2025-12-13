<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAdmin } from 'dashboard/composables/useAdmin';
import Banner from 'dashboard/components/ui/Banner.vue';
import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';

const DISMISS_DURATION_MS = 24 * 60 * 60 * 1000; // 24 hours

const store = useStore();
const { t, locale } = useI18n();
const { isAdmin } = useAdmin();

const isDismissed = ref(false);

const fazerAiSubscription = computed(
  () => store.getters['globalConfig/getFazerAiSubscription']
);
const isFazerAiSubscriptionPastDue = computed(
  () => store.getters['globalConfig/isFazerAiSubscriptionPastDue']
);
const isFazerAiSubscriptionCanceling = computed(
  () => store.getters['globalConfig/isFazerAiSubscriptionCanceling']
);
const currentUser = computed(() => store.getters.getCurrentUser);

const isSuperAdmin = computed(() => currentUser.value?.type === 'SuperAdmin');

const resolvedLocale = computed(() => {
  const currentLocale = locale.value || navigator.language || 'en';
  return currentLocale.replace('_', '-');
});

const formattedPeriodEnd = computed(() => {
  const periodEnd = fazerAiSubscription.value?.current_period_end;
  if (!periodEnd) return '';
  const date = new Date(periodEnd * 1000);
  return new Intl.DateTimeFormat(resolvedLocale.value, {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  }).format(date);
});

const shouldShowBanner = computed(() => {
  if (
    !isFazerAiSubscriptionPastDue.value &&
    !isFazerAiSubscriptionCanceling.value
  )
    return false;
  if (!isAdmin.value) return false;
  if (isDismissed.value) return false;
  return true;
});

const bannerMessage = computed(() => {
  if (isFazerAiSubscriptionCanceling.value) {
    const key = isSuperAdmin.value
      ? 'FAZER_AI.SUBSCRIPTION_CANCELING.SUPERADMIN_MESSAGE'
      : 'FAZER_AI.SUBSCRIPTION_CANCELING.ADMIN_MESSAGE';
    return t(key, { date: formattedPeriodEnd.value });
  }
  const key = isSuperAdmin.value
    ? 'FAZER_AI.SUBSCRIPTION_PAST_DUE.SUPERADMIN_MESSAGE'
    : 'FAZER_AI.SUBSCRIPTION_PAST_DUE.ADMIN_MESSAGE';
  return t(key);
});

const actionButtonLabel = computed(() => {
  if (isFazerAiSubscriptionCanceling.value) {
    return t('FAZER_AI.SUBSCRIPTION_CANCELING.OPEN_BILLING');
  }
  return t('FAZER_AI.SUBSCRIPTION_PAST_DUE.OPEN_BILLING');
});

const billingUrl = computed(() => fazerAiSubscription.value?.billing_url || '');

function checkDismissedState() {
  const dismissedAt = LocalStorage.get(
    LOCAL_STORAGE_KEYS.FAZER_AI_BANNER_DISMISSED_AT
  );
  if (dismissedAt) {
    const dismissedTime = new Date(dismissedAt).getTime();
    const now = Date.now();
    if (now - dismissedTime < DISMISS_DURATION_MS) {
      isDismissed.value = true;
    } else {
      LocalStorage.remove(LOCAL_STORAGE_KEYS.FAZER_AI_BANNER_DISMISSED_AT);
    }
  }
}

function onDismiss() {
  isDismissed.value = true;
  LocalStorage.set(
    LOCAL_STORAGE_KEYS.FAZER_AI_BANNER_DISMISSED_AT,
    new Date().toISOString()
  );
}

function openBilling() {
  if (billingUrl.value) {
    window.open(billingUrl.value, '_blank');
  }
}

onMounted(() => {
  checkDismissedState();
});
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <Banner
    v-if="shouldShowBanner"
    color-scheme="warning"
    :banner-message="bannerMessage"
    :action-button-label="isSuperAdmin ? actionButtonLabel : ''"
    :has-action-button="isSuperAdmin"
    has-close-button
    @primary-action="openBilling"
    @close="onDismiss"
  />
</template>
