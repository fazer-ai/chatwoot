<script>
import FluentIcon from 'shared/components/FluentIcon/Index.vue';

export default {
  components: {
    FluentIcon,
  },
  props: {
    url: {
      type: String,
      default: '',
    },
    isInProgress: {
      type: Boolean,
      default: false,
    },
    isUserBubble: {
      type: Boolean,
      default: false,
    },
  },
  computed: {
    title() {
      return this.isInProgress
        ? this.$t('COMPONENTS.FILE_BUBBLE.UPLOADING')
        : decodeURI(this.fileName);
    },
    fileName() {
      return this.url.substring(this.url.lastIndexOf('/') + 1);
    },
  },
  methods: {
    openLink() {
      const win = window.open(this.url, '_blank');
      win.focus();
    },
  },
};
</script>

<template>
  <div
    class="file flex flex-row items-center p-3 cursor-pointer"
    :class="{ 'file--user': isUserBubble }"
  >
    <div class="icon-wrap">
      <FluentIcon icon="document" size="28" />
    </div>
    <div class="ltr:pr-1 rtl:pl-1">
      <div class="file-name m-0 font-medium text-sm">
        {{ title }}
      </div>
      <div class="leading-none mb-1">
        <a
          class="download"
          rel="noreferrer noopener nofollow"
          target="_blank"
          :href="url"
        >
          {{ $t('COMPONENTS.FILE_BUBBLE.DOWNLOAD') }}
        </a>
      </div>
    </div>
  </div>
</template>

<style lang="scss" scoped>
// On the WhatsApp-styled bubble (light green for user, white for agent)
// we want the file name + download link to read in the same dark
// body text the bubble uses, not the dynamic contrasting-text-color
// the public widget computed off `widgetColor`. That contrast helper
// returned white for the dark WhatsApp brand green, which was
// unreadable on our actual light-green bubble fill.
.file {
  .icon-wrap {
    @apply text-[2.5rem] leading-none ltr:ml-1 rtl:mr-1 ltr:mr-2 rtl:ml-2;

    color: #008069;
  }

  .file-name {
    color: #111b21;
  }

  .download {
    @apply font-medium p-0 m-0 text-xs no-underline;

    color: #027eb5;
  }

  // Dark-mode mirror.
  .dark & {
    .icon-wrap {
      color: #00a884;
    }
    .file-name {
      color: #e9edef;
    }
    .download {
      color: #53bdeb;
    }
  }
}
</style>
