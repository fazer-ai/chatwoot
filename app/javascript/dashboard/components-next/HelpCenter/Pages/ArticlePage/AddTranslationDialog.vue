<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import categoriesAPI from 'dashboard/api/helpCenter/categories.js';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

const props = defineProps({
  article: {
    type: Object,
    default: null,
  },
  allowedLocales: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['translationCreated']);

const { t } = useI18n();
const store = useStore();
const route = useRoute();

const currentUserId = useMapGetter('getCurrentUserID');

const dialogRef = ref(null);
const isSubmitting = ref(false);
const selectedLocale = ref('');
const selectedCategoryId = ref('');
const targetCategories = ref([]);
const isFetchingCategories = ref(false);

const existingLocales = computed(() => {
  if (!props.article) return [];
  const locales = (props.article.associatedArticles || []).map(
    associated => associated.locale
  );
  return [props.article.locale, ...locales].filter(Boolean);
});

const localeOptions = computed(() => {
  return props.allowedLocales
    .filter(locale => !existingLocales.value.includes(locale.code))
    .map(locale => ({
      value: locale.code,
      label: `${locale.name} (${locale.code})`,
    }));
});

const hasAvailableLocales = computed(() => localeOptions.value.length > 0);

const categoryOptions = computed(() => {
  return targetCategories.value.map(category => ({
    value: category.id,
    label: category.name,
  }));
});

const isConfirmDisabled = computed(() => {
  return !selectedLocale.value || isSubmitting.value;
});

const fetchCategoriesForLocale = async locale => {
  if (!locale) {
    targetCategories.value = [];
    return;
  }

  isFetchingCategories.value = true;
  try {
    const { data } = await categoriesAPI.get({
      portalSlug: route.params.portalSlug,
      locale,
    });
    targetCategories.value = data.payload;
  } catch {
    targetCategories.value = [];
  } finally {
    isFetchingCategories.value = false;
  }
};

watch(selectedLocale, newLocale => {
  selectedCategoryId.value = '';
  fetchCategoriesForLocale(newLocale);
});

const resetForm = () => {
  selectedLocale.value = '';
  selectedCategoryId.value = '';
  targetCategories.value = [];
};

const onConfirm = async () => {
  if (isConfirmDisabled.value || !props.article) return;

  isSubmitting.value = true;
  try {
    const articleId = await store.dispatch('articles/create', {
      portalSlug: route.params.portalSlug,
      title: props.article.title,
      content: props.article.content,
      description: props.article.description,
      locale: selectedLocale.value,
      authorId: currentUserId.value,
      categoryId: selectedCategoryId.value || undefined,
      associatedArticleId: props.article.id,
    });

    useAlert(
      t('HELP_CENTER.ARTICLES_PAGE.ADD_TRANSLATION.API.SUCCESS_MESSAGE')
    );
    const locale = selectedLocale.value;
    resetForm();
    dialogRef.value?.close();
    emit('translationCreated', { articleId, locale });
  } catch (error) {
    useAlert(
      error?.message ||
        t('HELP_CENTER.ARTICLES_PAGE.ADD_TRANSLATION.API.ERROR_MESSAGE')
    );
  } finally {
    isSubmitting.value = false;
  }
};

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    :title="t('HELP_CENTER.ARTICLES_PAGE.ADD_TRANSLATION.TITLE')"
    :description="t('HELP_CENTER.ARTICLES_PAGE.ADD_TRANSLATION.DESCRIPTION')"
    :confirm-button-label="
      t('HELP_CENTER.ARTICLES_PAGE.ADD_TRANSLATION.CONFIRM')
    "
    :disable-confirm-button="isConfirmDisabled"
    :is-loading="isSubmitting"
    @close="resetForm"
    @confirm="onConfirm"
  >
    <div v-if="hasAvailableLocales" class="flex flex-col gap-6">
      <div class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('HELP_CENTER.ARTICLES_PAGE.ADD_TRANSLATION.LOCALE_LABEL') }}
        </span>
        <ComboBox
          v-model="selectedLocale"
          :options="localeOptions"
          :placeholder="
            t('HELP_CENTER.ARTICLES_PAGE.ADD_TRANSLATION.LOCALE_PLACEHOLDER')
          "
          class="[&>div>button:not(.focused)]:!outline-n-slate-5 [&>div>button:not(.focused)]:dark:!outline-n-slate-5"
        />
      </div>
      <div class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('HELP_CENTER.ARTICLES_PAGE.ADD_TRANSLATION.CATEGORY_LABEL') }}
          <span class="text-n-slate-10 font-normal">
            {{ t('HELP_CENTER.ARTICLES_PAGE.ADD_TRANSLATION.OPTIONAL') }}
          </span>
        </span>
        <ComboBox
          v-model="selectedCategoryId"
          :options="categoryOptions"
          :disabled="!selectedLocale || isFetchingCategories"
          :placeholder="
            t('HELP_CENTER.ARTICLES_PAGE.ADD_TRANSLATION.CATEGORY_PLACEHOLDER')
          "
          class="[&>div>button:not(.focused)]:!outline-n-slate-5 [&>div>button:not(.focused)]:dark:!outline-n-slate-5"
        />
      </div>
    </div>
    <p v-else class="text-sm text-n-slate-11 m-0">
      {{ t('HELP_CENTER.ARTICLES_PAGE.ADD_TRANSLATION.NO_LOCALES') }}
    </p>
  </Dialog>
</template>
