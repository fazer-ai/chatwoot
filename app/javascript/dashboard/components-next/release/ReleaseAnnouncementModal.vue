<script setup>
import { computed, ref, watch, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t, locale } = useI18n();
const { formatMessage } = useMessageFormatter();

const dialogRef = ref(null);

const unseenTag = computed(
  () => store.getters.getCurrentUser?.unseen_release_tag || null
);
const releases = computed(() => store.getters['releases/getReleases']);
const uiFlags = computed(() => store.getters['releases/getUIFlags']);

// Operations Notifications take precedence over Release Notes — when an
// ops broadcast is pending, the user must acknowledge it before seeing
// the release modal. Once the ops queue drains, the existing watcher
// reacts (`featuredRelease` re-evaluates as soon as `hasPendingOps`
// flips to false) and opens the release dialog naturally.
const hasPendingOps = computed(
  () => store.getters['operationsNotifications/hasPending']
);

const localeKey = computed(() => (locale.value === 'pt_BR' ? 'pt_BR' : 'en'));

const featuredRelease = computed(() => {
  if (!unseenTag.value) return null;
  if (hasPendingOps.value) return null;
  return releases.value.find(rel => rel.tag === unseenTag.value) || null;
});

const featuredBodyHtml = computed(() => {
  if (!featuredRelease.value) return '';
  const primary = featuredRelease.value.notes?.[localeKey.value];
  const fallback =
    featuredRelease.value.notes?.[localeKey.value === 'pt_BR' ? 'en' : 'pt_BR'];
  return formatMessage(primary || fallback || '', false, false, false);
});

watch(
  unseenTag,
  newTag => {
    if (!newTag) return;
    if (uiFlags.value.fetchingList) return;
    if (releases.value.length === 0) {
      store.dispatch('releases/fetch');
    }
  },
  { immediate: false }
);

watch(featuredRelease, rel => {
  if (rel) {
    dialogRef.value?.open();
  }
});

const dismiss = async () => {
  if (!unseenTag.value) {
    dialogRef.value?.close();
    return;
  }
  await store.dispatch('releases/dismiss', unseenTag.value);
  dialogRef.value?.close();
};

const goToAll = async () => {
  await dismiss();
  router.push({
    name: 'release_notes_index',
    params: { accountId: route.params.accountId },
  });
};

onMounted(() => {
  if (unseenTag.value) {
    store.dispatch('releases/fetch');
  }
});
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="2xl"
    position="top"
    :show-cancel-button="false"
    :show-confirm-button="false"
    :title="t('RELEASE_NOTES.MODAL_TITLE')"
    :description="
      featuredRelease
        ? t('RELEASE_NOTES.MODAL_SUBTITLE', { tag: featuredRelease.tag })
        : ''
    "
    @close="dismiss"
  >
    <div v-if="featuredRelease" class="flex flex-col gap-4">
      <article
        class="prose prose-sm max-w-none dark:prose-invert prose-headings:text-n-slate-12 prose-strong:text-n-slate-12 prose-a:text-n-blue-11"
        v-html="featuredBodyHtml"
      />
    </div>
    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          variant="faded"
          color="slate"
          :label="t('RELEASE_NOTES.SEE_ALL')"
          type="button"
          @click="goToAll"
        />
        <Button
          color="blue"
          :label="t('RELEASE_NOTES.DISMISS')"
          type="button"
          :is-loading="uiFlags.isDismissing"
          @click="dismiss"
        />
      </div>
    </template>
  </Dialog>
</template>
