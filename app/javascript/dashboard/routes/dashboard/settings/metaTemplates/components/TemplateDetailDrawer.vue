<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import StatusBadge from './StatusBadge.vue';

const props = defineProps({
  template: { type: Object, default: null },
  open: { type: Boolean, default: false },
});

const emit = defineEmits(['close']);

const { t } = useI18n();

// Meta templates use a `components` array with typed entries. Pull each
// section into its own computed so the template markup stays flat.
// Header, footer and buttons are optional; body is mandatory in Meta's
// contract and therefore assumed present here.
const componentByType = type => {
  return (props.template?.components || []).find(
    c => (c?.type || '').toUpperCase() === type
  );
};

const header = computed(() => componentByType('HEADER'));
const body = computed(() => componentByType('BODY'));
const footer = computed(() => componentByType('FOOTER'));
const buttonsComponent = computed(() => componentByType('BUTTONS'));
const buttons = computed(() => buttonsComponent.value?.buttons || []);

const bodyText = computed(() => body.value?.text || '');
const footerText = computed(() => footer.value?.text || '');

// Header can be TEXT / IMAGE / VIDEO / DOCUMENT / LOCATION. For TEXT we
// show the string with placeholder highlighting via the body renderer;
// for media types we just label the format — Fatia 5 will add rich
// preview.
const headerFormat = computed(() =>
  (header.value?.format || 'TEXT').toUpperCase()
);
const headerText = computed(() => header.value?.text || '');

const rejectedReason = computed(() => props.template?.rejected_reason);
</script>

<template>
  <transition name="slide">
    <aside
      v-if="open && template"
      class="fixed top-0 right-0 h-full w-full max-w-xl bg-n-solid-1 border-l border-n-weak shadow-2xl z-40 flex flex-col"
    >
      <header
        class="flex items-start justify-between p-5 border-b border-n-weak gap-3"
      >
        <div class="min-w-0">
          <h2 class="text-base font-semibold text-n-slate-12 truncate">
            {{ template.name }}
          </h2>
          <p class="text-xs text-n-slate-11 mt-0.5">
            {{ template.category }}
            {{ t('META_TEMPLATES.DETAIL.SUBTITLE_SEPARATOR') }}
            {{ template.language }}
          </p>
        </div>
        <div class="flex items-center gap-2 flex-shrink-0">
          <StatusBadge :status="template.status" />
          <button
            type="button"
            class="text-n-slate-11 hover:text-n-slate-12 text-sm leading-none px-2 py-1 rounded hover:bg-n-alpha-1"
            @click="emit('close')"
          >
            {{ t('META_TEMPLATES.DETAIL.CLOSE') }}
          </button>
        </div>
      </header>

      <div class="flex-1 overflow-y-auto p-5 space-y-4">
        <div
          v-if="rejectedReason"
          class="px-3 py-2 rounded-md bg-n-ruby-3 text-n-ruby-12 text-sm"
        >
          <strong>{{
            t('META_TEMPLATES.DETAIL.REJECTED_REASON_LABEL')
          }}</strong>
          {{ rejectedReason }}
        </div>

        <section v-if="header" class="border border-n-weak rounded-lg p-3">
          <div class="text-xxs uppercase tracking-wide text-n-slate-11 mb-2">
            {{
              t('META_TEMPLATES.DETAIL.HEADER_FORMAT_LABEL', {
                label: t('META_TEMPLATES.DETAIL.HEADER'),
                format: headerFormat,
              })
            }}
          </div>
          <p
            v-if="headerFormat === 'TEXT'"
            class="text-sm text-n-slate-12 whitespace-pre-wrap"
          >
            {{ headerText || '—' }}
          </p>
          <p v-else class="text-xs text-n-slate-11">
            {{
              t('META_TEMPLATES.DETAIL.MEDIA_HEADER_NOTE', {
                format: headerFormat,
              })
            }}
          </p>
        </section>

        <section class="border border-n-weak rounded-lg p-3">
          <div class="text-xxs uppercase tracking-wide text-n-slate-11 mb-2">
            {{ t('META_TEMPLATES.DETAIL.BODY') }}
          </div>
          <p class="text-sm text-n-slate-12 whitespace-pre-wrap">
            {{ bodyText || '—' }}
          </p>
        </section>

        <section v-if="footerText" class="border border-n-weak rounded-lg p-3">
          <div class="text-xxs uppercase tracking-wide text-n-slate-11 mb-2">
            {{ t('META_TEMPLATES.DETAIL.FOOTER') }}
          </div>
          <p class="text-sm text-n-slate-12 whitespace-pre-wrap">
            {{ footerText }}
          </p>
        </section>

        <section
          v-if="buttons.length"
          class="border border-n-weak rounded-lg p-3"
        >
          <div class="text-xxs uppercase tracking-wide text-n-slate-11 mb-2">
            {{ t('META_TEMPLATES.DETAIL.BUTTONS') }}
          </div>
          <ul class="grid gap-2">
            <li
              v-for="(button, idx) in buttons"
              :key="idx"
              class="px-3 py-1.5 bg-n-alpha-1 rounded-md text-sm text-n-slate-12"
            >
              <span
                class="text-xxs uppercase tracking-wide text-n-slate-11 mr-2"
              >
                {{ button.type }}
              </span>
              {{ button.text }}
              <span v-if="button.url" class="text-xs text-n-slate-11 ml-2">
                {{ t('META_TEMPLATES.DETAIL.URL_PREFIX') }} {{ button.url }}
              </span>
              <span
                v-if="button.phone_number"
                class="text-xs text-n-slate-11 ml-2"
              >
                {{ t('META_TEMPLATES.DETAIL.PHONE_PREFIX') }}
                {{ button.phone_number }}
              </span>
            </li>
          </ul>
        </section>
      </div>
    </aside>
  </transition>
</template>

<style scoped>
.slide-enter-active,
.slide-leave-active {
  transition: transform 0.2s ease;
}
.slide-enter-from,
.slide-leave-to {
  transform: translateX(100%);
}
</style>
