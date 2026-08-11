<script setup>
import { useI18n } from 'vue-i18n';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';

const { t } = useI18n();
</script>

<template>
  <SettingsLayout
    no-records-found
    :no-records-message="t('META_TEMPLATES.COMING_SOON.MESSAGE')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('META_TEMPLATES.HEADER.TITLE')"
        :description="t('META_TEMPLATES.HEADER.DESCRIPTION')"
      />
    </template>
  </SettingsLayout>
</template>
