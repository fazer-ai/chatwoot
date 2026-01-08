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
const isFazerAiSubscriptionTrialing = computed(
  () => store.getters['globalConfig/isFazerAiSubscriptionTrialing']
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

const daysUntilTrialEnd = computed(() => {
  const periodEnd = fazerAiSubscription.value?.current_period_end;
  if (!periodEnd) return null;
  const endDate = new Date(periodEnd * 1000);
  const now = new Date();
  const diffTime = endDate.getTime() - now.getTime();
  const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
  return Math.max(0, diffDays);
});

const shouldShowBanner = computed(() => {
  if (
    !isFazerAiSubscriptionPastDue.value &&
    !isFazerAiSubscriptionCanceling.value &&
    !isFazerAiSubscriptionTrialing.value
  )
    return false;
  if (isDismissed.value) return false;
  return true;
});

const bannerColorScheme = computed(() => {
  if (isFazerAiSubscriptionTrialing.value) {
    const days = daysUntilTrialEnd.value;
    if (days !== null && days <= 3) return 'warning';
    return 'primary';
  }
  return 'warning';
});

const bannerMessage = computed(() => {
  if (isFazerAiSubscriptionTrialing.value) {
    const days = daysUntilTrialEnd.value;
    if (!isAdmin.value) {
      if (days === 0) {
        return t('FAZER_AI.SUBSCRIPTION_TRIALING.USER_MESSAGE_LAST_DAY');
      }
      if (days !== null && days <= 7) {
        return t('FAZER_AI.SUBSCRIPTION_TRIALING.USER_MESSAGE_DAYS', { days });
      }
      return t('FAZER_AI.SUBSCRIPTION_TRIALING.USER_MESSAGE', {
        date: formattedPeriodEnd.value,
      });
    }
    if (days === 0) {
      return t('FAZER_AI.SUBSCRIPTION_TRIALING.MESSAGE_LAST_DAY');
    }
    if (days !== null && days <= 7) {
      return t('FAZER_AI.SUBSCRIPTION_TRIALING.MESSAGE_DAYS', { days });
    }
    return t('FAZER_AI.SUBSCRIPTION_TRIALING.MESSAGE', {
      date: formattedPeriodEnd.value,
    });
  }
  if (isFazerAiSubscriptionCanceling.value) {
    if (!isAdmin.value) {
      return t('FAZER_AI.SUBSCRIPTION_CANCELING.USER_MESSAGE', {
        date: formattedPeriodEnd.value,
      });
    }
    const key = isSuperAdmin.value
      ? 'FAZER_AI.SUBSCRIPTION_CANCELING.SUPERADMIN_MESSAGE'
      : 'FAZER_AI.SUBSCRIPTION_CANCELING.ADMIN_MESSAGE';
    return t(key, { date: formattedPeriodEnd.value });
  }
  if (!isAdmin.value) {
    return t('FAZER_AI.SUBSCRIPTION_PAST_DUE.USER_MESSAGE');
  }
  const key = isSuperAdmin.value
    ? 'FAZER_AI.SUBSCRIPTION_PAST_DUE.SUPERADMIN_MESSAGE'
    : 'FAZER_AI.SUBSCRIPTION_PAST_DUE.ADMIN_MESSAGE';
  return t(key);
});

const actionButtonLabel = computed(() => {
  if (isFazerAiSubscriptionTrialing.value) {
    return t('FAZER_AI.SUBSCRIPTION_TRIALING.UPGRADE');
  }
  if (isFazerAiSubscriptionCanceling.value) {
    return t('FAZER_AI.SUBSCRIPTION_CANCELING.OPEN_BILLING');
  }
  return t('FAZER_AI.SUBSCRIPTION_PAST_DUE.OPEN_BILLING');
});

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

function openSubscriptionSettings() {
  window.location.href = '/super_admin/settings';
}

onMounted(() => {
  checkDismissedState();
});
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <Banner
    v-if="shouldShowBanner"
    :color-scheme="bannerColorScheme"
    :banner-message="bannerMessage"
    :action-button-label="isSuperAdmin ? actionButtonLabel : ''"
    :has-action-button="isSuperAdmin"
    has-close-button
    @primary-action="openSubscriptionSettings"
    @close="onDismiss"
  />
</template>
