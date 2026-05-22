<script setup>
import OnboardingFeatureCard from './OnboardingFeatureCard.vue';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters, useMapGetter } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const getters = useStoreGetters();
const { t } = useI18n();
const globalConfig = computed(() => getters['globalConfig/get'].value);
const currentUser = computed(() => getters.getCurrentUser.value);

// Account-level test/production flag drives the alternate banner copy +
// CTA button below. We read it via the same getter pattern the sidebar
// uses so a Super Admin flip propagates without page reload.
const accountId = useMapGetter('getCurrentAccountId');
const accountGetter = useMapGetter('accounts/getAccount');
const isTestEnvironment = computed(
  () => accountGetter.value(accountId.value)?.environment === 'test'
);
const openSimulator = () => {
  emitter.emit(BUS_EVENTS.OPEN_SIMULATOR);
};

const greetingMessage = computed(() => {
  const hours = new Date().getHours();
  let translationKey;
  if (hours < 12) {
    translationKey = 'ONBOARDING.GREETING_MORNING';
  } else if (hours < 18) {
    translationKey = 'ONBOARDING.GREETING_AFTERNOON';
  } else {
    translationKey = 'ONBOARDING.GREETING_EVENING';
  }
  return t(translationKey, {
    name: currentUser.value.name,
    installationName: globalConfig.value.installationName,
  });
});
</script>

<template>
  <div
    class="min-h-screen lg:max-w-5xl max-w-4xl mx-auto grid grid-cols-2 grid-rows-[auto_1fr_1fr] auto-rows-min gap-4 p-8 w-full font-inter overflow-auto"
  >
    <div class="col-span-full self-start">
      <p
        class="text-xl font-semibold text-n-slate-12 font-interDisplay tracking-[0.3px]"
      >
        {{ greetingMessage }}
      </p>
      <template v-if="isTestEnvironment">
        <p class="text-n-slate-11 max-w-2xl text-base">
          {{
            $t('ONBOARDING.TEST_ENVIRONMENT.DESCRIPTION_PREFIX', {
              installationName: globalConfig.installationName,
            })
          }}
        </p>
        <button
          type="button"
          class="inline-flex items-center gap-2 mt-4 px-4 py-2 rounded-lg bg-n-amber-9 hover:bg-n-amber-10 text-white text-sm font-medium shadow-sm"
          @click="openSimulator"
        >
          <span class="i-lucide-flask-conical size-4" />
          {{ $t('ONBOARDING.TEST_ENVIRONMENT.SIMULATOR_BUTTON') }}
          <span class="i-lucide-external-link size-3.5" />
        </button>
        <p class="text-n-slate-11 max-w-2xl text-base mt-4">
          {{
            $t('ONBOARDING.TEST_ENVIRONMENT.DESCRIPTION_SUFFIX', {
              installationName: globalConfig.installationName,
            })
          }}
        </p>
      </template>
      <p v-else class="text-n-slate-11 max-w-2xl text-base">
        {{
          $t('ONBOARDING.DESCRIPTION', {
            installationName: globalConfig.installationName,
          })
        }}
      </p>
    </div>
    <OnboardingFeatureCard
      image-src="/dashboard/images/onboarding/omnichannel-inbox.png"
      image-alt="Omnichannel"
      to="settings_inbox_new"
      :title="$t('ONBOARDING.ALL_CONVERSATION.TITLE')"
      :description="$t('ONBOARDING.ALL_CONVERSATION.DESCRIPTION')"
      :link-text="$t('ONBOARDING.ALL_CONVERSATION.NEW_LINK')"
    />
    <OnboardingFeatureCard
      image-src="/dashboard/images/onboarding/teams.png"
      image-alt="Teams"
      to="settings_teams_new"
      :title="$t('ONBOARDING.TEAM_MEMBERS.TITLE')"
      :description="$t('ONBOARDING.TEAM_MEMBERS.DESCRIPTION')"
      :link-text="$t('ONBOARDING.TEAM_MEMBERS.NEW_LINK')"
    />
    <OnboardingFeatureCard
      image-src="/dashboard/images/onboarding/canned-responses.png"
      image-alt="Canned responses"
      to="canned_list"
      :title="$t('ONBOARDING.CANNED_RESPONSES.TITLE')"
      :description="$t('ONBOARDING.CANNED_RESPONSES.DESCRIPTION')"
      :link-text="$t('ONBOARDING.CANNED_RESPONSES.NEW_LINK')"
    />
    <OnboardingFeatureCard
      image-src="/dashboard/images/onboarding/labels.png"
      image-alt="Labels"
      to="labels_list"
      :title="$t('ONBOARDING.LABELS.TITLE')"
      :description="$t('ONBOARDING.LABELS.DESCRIPTION')"
      :link-text="$t('ONBOARDING.LABELS.NEW_LINK')"
    />
  </div>
</template>
