<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  referral: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

// content_attributes keys are deep-camelized by MessageList (useCamelCase),
// so the referral payload arrives as sourceUrl/thumbnailUrl/etc.
const hasImageError = ref(false);
const showImage = computed(
  () => Boolean(props.referral.thumbnailUrl) && !hasImageError.value
);
</script>

<template>
  <component
    :is="referral.sourceUrl ? 'a' : 'div'"
    :href="referral.sourceUrl || undefined"
    :target="referral.sourceUrl ? '_blank' : undefined"
    rel="noopener noreferrer"
    class="flex flex-col gap-2 p-2 -mx-1 mb-2 overflow-hidden no-underline rounded-lg bg-n-alpha-black1"
    :class="referral.sourceUrl ? 'cursor-pointer hover:bg-n-alpha-black2' : ''"
  >
    <div class="flex items-center gap-1 text-xs text-n-slate-11">
      <Icon icon="i-lucide-megaphone" class="size-3" />
      <span>{{ t('COMPONENTS.REFERRAL_CARD.AD_LABEL') }}</span>
    </div>
    <img
      v-if="showImage"
      :src="referral.thumbnailUrl"
      class="object-cover w-full rounded max-h-44 skip-context-menu"
      @error="hasImageError = true"
    />
    <div class="min-w-0">
      <p v-if="referral.title" class="mb-0 text-sm font-medium line-clamp-2">
        {{ referral.title }}
      </p>
      <p v-if="referral.body" class="mb-0 text-xs text-n-slate-11 line-clamp-2">
        {{ referral.body }}
      </p>
    </div>
    <div
      v-if="referral.sourceUrl"
      class="flex items-center gap-1 text-xs font-medium text-n-slate-12"
    >
      <Icon icon="i-lucide-external-link" class="size-3 shrink-0" />
      <span>{{ t('COMPONENTS.REFERRAL_CARD.VIEW_AD') }}</span>
    </div>
  </component>
</template>
