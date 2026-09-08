<script>
import CustomButton from 'shared/components/Button.vue';
import TextArea from 'shared/components/TextArea.vue';
import Spinner from 'shared/components/Spinner.vue';

export default {
  name: 'Feedback',
  components: {
    CustomButton,
    TextArea,
    Spinner,
  },
  props: {
    isUpdating: {
      type: Boolean,
      default: false,
    },
    isButtonDisabled: {
      type: Boolean,
      default: false,
    },
    selectedRating: {
      type: Number,
      default: null,
    },
  },
  emits: ['sendFeedback'],
  data() {
    return {
      feedback: '',
    };
  },
  computed: {
    isSubmitDisabled() {
      return (
        this.isButtonDisabled || !this.selectedRating || !this.feedback.trim()
      );
    },
  },
  methods: {
    onClick() {
      if (this.isSubmitDisabled) return;
      this.$emit('sendFeedback', this.feedback);
    },
  },
};
</script>

<template>
  <div class="mt-8 border-t border-n-weak pt-6">
    <label
      for="survey-feedback"
      class="text-base font-medium leading-snug text-n-slate-12"
    >
      {{ $t('SURVEY.FEEDBACK.LABEL') }}
    </label>
    <TextArea
      id="survey-feedback"
      v-model="feedback"
      class="my-5"
      :placeholder="$t('SURVEY.FEEDBACK.PLACEHOLDER')"
    />
    <div
      class="flex flex-col items-stretch font-medium sm:flex-row sm:justify-end"
    >
      <!-- Escurece no hover, nao clareia: --survey-brand ja vem de BrandColor.on_light, que
           para exatamente em 4.5:1 contra o branco. Clarear o fundo 10% derruba o rotulo
           branco para 3,9-4,2:1 em toda marca medida, inclusive na cor padrao. -->
      <CustomButton
        :disabled="isSubmitDisabled"
        bg-color="var(--survey-brand)"
        class="w-full !rounded-xl !py-3.5 text-base font-semibold transition-all duration-200 hover:brightness-90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[color:var(--survey-brand)] sm:w-auto sm:!px-8"
        @click="onClick"
      >
        <Spinner v-if="isUpdating" class="p-0" />
        {{ $t('SURVEY.FEEDBACK.BUTTON_TEXT') }}
      </CustomButton>
    </div>
  </div>
</template>
