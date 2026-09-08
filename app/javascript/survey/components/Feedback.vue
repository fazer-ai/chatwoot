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
  <div class="mt-6">
    <label for="survey-feedback" class="text-base font-medium text-n-slate-12">
      {{ $t('SURVEY.FEEDBACK.LABEL') }}
    </label>
    <TextArea
      id="survey-feedback"
      v-model="feedback"
      class="my-5"
      :placeholder="$t('SURVEY.FEEDBACK.PLACEHOLDER')"
    />
    <div class="flex justify-end font-medium">
      <CustomButton
        :disabled="isSubmitDisabled"
        bg-color="var(--survey-brand)"
        class="w-full sm:w-auto hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[color:var(--survey-brand)]"
        @click="onClick"
      >
        <Spinner v-if="isUpdating" class="p-0" />
        {{ $t('SURVEY.FEEDBACK.BUTTON_TEXT') }}
      </CustomButton>
    </div>
  </div>
</template>
