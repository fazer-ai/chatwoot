<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import {
  formatPrice,
  isReadableProduct,
  toHttpUrl,
  toImageDataUri,
} from './catalogHelpers';

// A product sent from a WhatsApp catalog, drawn the way WhatsApp draws it: the photo on
// top, then the name, the price and the description. The photo is the message's image
// attachment when the connector delivered it, the inline thumbnail until then.
const props = defineProps({
  product: { type: Object, required: true },
  imageUrl: { type: String, default: null },
});

const { t, locale } = useI18n();

const imageFailed = ref(false);
const thumbnail = computed(() => toImageDataUri(props.product.thumbnail));
const imageSrc = computed(() => {
  if (props.imageUrl && !imageFailed.value) return props.imageUrl;
  return thumbnail.value;
});

const readable = computed(() => isReadableProduct(props.product));
const currentPrice = computed(() =>
  formatPrice(
    props.product.salePrice1000 ?? props.product.price1000,
    props.product.currency,
    locale.value
  )
);
const originalPrice = computed(() =>
  typeof props.product.salePrice1000 === 'number'
    ? formatPrice(props.product.price1000, props.product.currency, locale.value)
    : null
);
const productUrl = computed(() => toHttpUrl(props.product.url));
</script>

<template>
  <div class="flex flex-col gap-2" data-catalog-card="product">
    <img
      v-if="imageSrc"
      :src="imageSrc"
      :alt="product.title || ''"
      class="object-cover w-full rounded-lg max-h-72 bg-n-alpha-black1"
      @error="imageFailed = true"
    />
    <div class="flex items-center gap-1 text-xs text-n-slate-11">
      <Icon icon="i-lucide-store" class="size-3 shrink-0" />
      <span>{{ t('CONVERSATION.CATALOG.PRODUCT_LABEL') }}</span>
    </div>
    <template v-if="readable">
      <p class="mb-0 font-medium">{{ product.title }}</p>
      <p v-if="currentPrice" class="flex flex-wrap items-baseline gap-2 mb-0">
        <span class="font-medium">{{ currentPrice }}</span>
        <s v-if="originalPrice" class="text-xs text-n-slate-11">
          {{ originalPrice }}
        </s>
      </p>
      <p
        v-if="product.description"
        class="mb-0 text-n-slate-11 line-clamp-4 whitespace-pre-line"
      >
        {{ product.description }}
      </p>
    </template>
    <p v-else class="mb-0 text-n-slate-11">
      {{ t('CONVERSATION.CATALOG.PRODUCT_UNREADABLE') }}
    </p>
    <a
      v-if="productUrl"
      :href="productUrl"
      target="_blank"
      rel="noopener noreferrer"
      class="flex items-center justify-center gap-1 px-3 py-1.5 text-sm font-medium no-underline rounded-lg bg-n-alpha-black1 hover:bg-n-alpha-black2 text-n-slate-12"
    >
      <Icon icon="i-lucide-external-link" class="size-3 shrink-0" />
      <span>{{ t('CONVERSATION.CATALOG.VIEW') }}</span>
    </a>
  </div>
</template>
