<script>
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { CONTACTS_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import { vOnClickOutside } from '@vueuse/components';
import { useTrack } from 'dashboard/composables';
import NextButton from 'next/button/Button.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
import VisibilitySelector from 'dashboard/components-next/filter/VisibilitySelector.vue';

export default {
  components: {
    NextButton,
    NextInput,
    VisibilitySelector,
  },
  directives: {
    onClickOutside: vOnClickOutside,
  },
  props: {
    filterType: {
      type: Number,
      default: 0,
    },
    customViewsQuery: {
      type: Object,
      default: () => {},
    },
    openLastSavedItem: {
      type: Function,
      default: () => {},
    },
  },
  emits: ['close'],
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      show: true,
      name: '',
      visibility: 'personal',
    };
  },

  computed: {
    isButtonDisabled() {
      return this.v$.name.$invalid;
    },
    // Backend allows both administrators and managers to create/edit
    // global custom filters (see CustomFilterPolicy + CustomFilter#set_visibility,
    // which only downgrades to `personal` for agents). Keeping this gated on
    // administrator only silently forces managers into personal filters —
    // the visibility selector never renders, so a manager cannot create a
    // clinic-wide folder even though the API would accept it.
    canManageGlobalFilters() {
      return ['administrator', 'manager'].includes(
        this.$store.getters.getCurrentRole
      );
    },
  },

  validations: {
    name: {
      required,
      minLength: minLength(1),
    },
  },

  methods: {
    onClose() {
      this.$emit('close');
    },
    async saveCustomViews() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        return;
      }
      try {
        await this.$store.dispatch('customViews/create', {
          name: this.name,
          filter_type: this.filterType,
          visibility: this.visibility,
          query: this.customViewsQuery,
        });
        this.alertMessage =
          this.filterType === 0
            ? this.$t('FILTER.CUSTOM_VIEWS.ADD.API_FOLDERS.SUCCESS_MESSAGE')
            : this.$t('FILTER.CUSTOM_VIEWS.ADD.API_SEGMENTS.SUCCESS_MESSAGE');
        this.onClose();

        useTrack(CONTACTS_EVENTS.SAVE_FILTER, {
          type: this.filterType === 0 ? 'folder' : 'segment',
        });
        this.openLastSavedItem();
      } catch (error) {
        const fallbackMessage =
          this.filterType === 0
            ? this.$t('FILTER.CUSTOM_VIEWS.ADD.API_FOLDERS.ERROR_MESSAGE')
            : this.$t('FILTER.CUSTOM_VIEWS.ADD.API_SEGMENTS.ERROR_MESSAGE');
        this.alertMessage = error?.message || fallbackMessage;
      } finally {
        useAlert(this.alertMessage);
      }
    },
  },
};
</script>

<template>
  <div
    v-on-click-outside="[
      () => $emit('close'),
      { ignore: ['#saveFilterTeleportTarget'] },
    ]"
    class="z-40 max-w-3xl lg:w-[500px] overflow-visible w-full border border-n-weak bg-n-alpha-3 backdrop-blur-[100px] shadow-lg rounded-xl p-6 grid gap-6"
  >
    <h3 class="text-base font-medium leading-6 text-n-slate-12">
      {{ $t('FILTER.CUSTOM_VIEWS.ADD.TITLE') }}
    </h3>
    <form class="w-full grid gap-6" @submit.prevent="saveCustomViews">
      <NextInput
        v-model="name"
        :placeholder="$t('FILTER.CUSTOM_VIEWS.ADD.PLACEHOLDER')"
        :message="v$.name.$error && $t('FILTER.CUSTOM_VIEWS.ADD.ERROR_MESSAGE')"
        :message-type="v$.name.$error && 'error'"
        @blur="v$.name.$touch"
      />
      <VisibilitySelector
        v-if="canManageGlobalFilters"
        v-model="visibility"
        i18n-prefix="FILTER.CUSTOM_VIEWS.VISIBILITY"
      />
      <div class="flex flex-row justify-end w-full gap-2">
        <NextButton faded slate sm @click.prevent="onClose">
          {{ $t('FILTER.CUSTOM_VIEWS.ADD.CANCEL_BUTTON') }}
        </NextButton>
        <NextButton solid blue sm :disabled="isButtonDisabled">
          {{ $t('FILTER.CUSTOM_VIEWS.ADD.SAVE_BUTTON') }}
        </NextButton>
      </div>
    </form>
  </div>
</template>
