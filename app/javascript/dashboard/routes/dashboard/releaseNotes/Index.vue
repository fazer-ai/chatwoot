<script setup>
import { computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const store = useStore();
const { t, locale } = useI18n();
const { formatMessage } = useMessageFormatter();

const releases = computed(() => store.getters['releases/getReleases']);
const uiFlags = computed(() => store.getters['releases/getUIFlags']);

const localeKey = computed(() => (locale.value === 'pt_BR' ? 'pt_BR' : 'en'));

const renderedReleases = computed(() =>
  releases.value.map(rel => {
    const primary = rel.notes?.[localeKey.value];
    const fallback = rel.notes?.[localeKey.value === 'pt_BR' ? 'en' : 'pt_BR'];
    return {
      ...rel,
      bodyHtml: formatMessage(primary || fallback || '', false, false, false),
    };
  })
);

const formatDate = published => {
  if (!published) return '';
  return new Date(published).toLocaleDateString(
    localeKey.value === 'pt_BR' ? 'pt-BR' : 'en-US',
    { year: 'numeric', month: 'short', day: '2-digit' }
  );
};

onMounted(() => {
  store.dispatch('releases/fetch');
});
</script>

<template>
  <div class="flex-1 min-h-0 overflow-y-auto">
    <div class="max-w-3xl px-6 py-6 mx-auto">
      <h1 class="text-xl font-semibold text-n-slate-12 mb-1">
        {{ t('RELEASE_NOTES.PAGE_TITLE') }}
      </h1>
      <p class="text-sm text-n-slate-11 mb-6">
        {{ t('RELEASE_NOTES.PAGE_DESCRIPTION') }}
      </p>

      <div
        v-if="uiFlags.fetchingList && releases.length === 0"
        class="flex justify-center py-12"
      >
        <Spinner />
      </div>

      <div
        v-else-if="releases.length === 0"
        class="px-6 py-12 text-sm text-center text-n-slate-11 border border-n-weak rounded-lg"
      >
        {{ t('RELEASE_NOTES.EMPTY_STATE') }}
      </div>

      <ol v-else class="flex flex-col gap-6">
        <li
          v-for="release in renderedReleases"
          :key="release.tag"
          class="bg-n-surface-1 border border-n-weak rounded-lg p-5"
        >
          <header class="flex items-baseline justify-between gap-3 mb-3">
            <h2 class="text-base font-semibold text-n-slate-12">
              {{ release.tag }}
            </h2>
            <span class="text-xs text-n-slate-11 flex-shrink-0">
              {{ formatDate(release.published_at) }}
            </span>
          </header>
          <article
            class="prose prose-sm max-w-none dark:prose-invert prose-headings:text-n-slate-12 prose-strong:text-n-slate-12 prose-a:text-n-blue-11"
            v-html="release.bodyHtml"
          />
        </li>
      </ol>
    </div>
  </div>
</template>
