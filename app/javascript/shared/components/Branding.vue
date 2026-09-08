<script>
import { useBranding } from 'shared/composables/useBranding';

const {
  LOGO_THUMBNAIL: logoThumbnail,
  BRAND_NAME: brandName,
  WIDGET_BRAND_URL: widgetBrandURL,
} = window.globalConfig || {};

export default {
  props: {
    disableBranding: {
      type: Boolean,
      default: false,
    },
    // Pages served on behalf of a single account pass that account's brand. Everything else
    // omits it and keeps the installation's, so the widget is untouched.
    brandName: {
      type: String,
      default: '',
    },
    // Whether the thumbnail is the mark of whoever this page belongs to, rather than a vendor
    // badge. Only that case drops the greyscale.
    ownLogo: {
      type: Boolean,
      default: false,
    },
  },
  setup() {
    const { replaceInstallationName } = useBranding();
    return {
      replaceInstallationName,
    };
  },
  data() {
    return {
      globalConfig: {
        brandName,
        logoThumbnail,
        widgetBrandURL,
      },
    };
  },
  computed: {
    displayedBrandName() {
      return this.brandName || this.globalConfig.brandName;
    },
    brandRedirectURL() {
      try {
        const referrerHost = this.$store.getters['appConfig/getReferrerHost'];
        const url = new URL(this.globalConfig.widgetBrandURL);
        if (referrerHost) {
          url.searchParams.set('utm_source', referrerHost);
          url.searchParams.set('utm_medium', 'widget');
        } else {
          url.searchParams.set('utm_medium', 'survey');
        }
        url.searchParams.set('utm_campaign', 'branding');
        return url.toString();
      } catch (e) {
        // Suppressing the error as getter is not defined in some cases
      }
      return '';
    },
  },
};
</script>

<template>
  <div
    v-if="displayedBrandName && !disableBranding"
    class="px-0 py-3 flex justify-center"
  >
    <a
      :href="brandRedirectURL"
      rel="noreferrer noopener nofollow"
      target="_blank"
      class="branding--link text-n-slate-11 hover:text-n-slate-12 cursor-pointer text-xs inline-flex hover:opacity-100 opacity-90 no-underline justify-center items-center leading-3"
      :class="{ 'grayscale-[1] hover:grayscale-0': !ownLogo }"
    >
      <!-- Greyscale suits a vendor badge, which is what this is by default. A page carrying the
           mark of whoever owns it is not a badge, so that one keeps its colour.
           max-w rather than a square box: an account's mark is a wide email header logo, and
           squeezing it into 12x12 leaves an illegible smudge. A square installation thumbnail
           still renders exactly as before. -->
      <img
        class="ltr:mr-1 rtl:ml-1 max-h-3 w-auto max-w-16 object-contain"
        :alt="displayedBrandName"
        :src="globalConfig.logoThumbnail"
      />
      <!-- Interpolated rather than run through replaceInstallationName: POWERED_BY is
           translated per locale, and in Persian and Tamil it carries a transliterated name
           instead of the Latin "Chatwoot", so the replace matches nothing and the footer would
           credit the vendor on a page already wearing the account's brand. Callers that pass
           brandName must ship POWERED_BY_BRAND in their bundle; the survey does. -->
      <span>
        {{
          brandName
            ? $t('POWERED_BY_BRAND', { brandName })
            : replaceInstallationName($t('POWERED_BY'))
        }}
      </span>
    </a>
  </div>
  <div v-else class="p-3" />
</template>
