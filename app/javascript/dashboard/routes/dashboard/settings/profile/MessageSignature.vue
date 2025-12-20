<script setup>
import { ref, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import WootMessageEditor from 'dashboard/components/widgets/WootWriter/Editor.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  messageSignature: {
    type: String,
    default: '',
  },
  signaturePosition: {
    type: String,
    // NOTE: 'top' or 'bottom'
    default: 'top',
  },
  signatureSeparator: {
    type: String,
    // NOTE: 'blank' or '--'
    default: 'blank',
  },
});

const emit = defineEmits(['updateSignature']);

const { t } = useI18n();
const { formatMessage } = useMessageFormatter();

const signature = ref(props.messageSignature);
const signaturePosition = ref(props.signaturePosition);
const signatureSeparator = ref(props.signatureSeparator);

const positionOptions = computed(() => [
  {
    value: 'top',
    label: t(
      'PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.SIGNATURE_POSITION.OPTIONS.TOP'
    ),
  },
  {
    value: 'bottom',
    label: t(
      'PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.SIGNATURE_POSITION.OPTIONS.BOTTOM'
    ),
  },
]);

const separatorOptions = computed(() => [
  {
    value: 'blank',
    label: t(
      'PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.SIGNATURE_SEPARATOR.OPTIONS.BLANK'
    ),
  },
  {
    value: '--',
    label: t(
      'PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.SIGNATURE_SEPARATOR.OPTIONS.HORIZONTAL_LINE'
    ),
  },
]);

const sampleMessage = computed(
  () =>
    `<p>${t('PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.PREVIEW.SAMPLE_MESSAGE')}</p>`
);

const formattedSignature = computed(() => {
  if (!signature.value) return '';
  return formatMessage(signature.value, false, false);
});

const messagePreview = computed(() => {
  if (!signature.value) return sampleMessage.value;

  const separator =
    signatureSeparator.value === 'blank' ? '<p></p>' : '<p>--</p>';

  if (signaturePosition.value === 'top') {
    return `${formattedSignature.value}${separator}${sampleMessage.value}`;
  }
  return `${sampleMessage.value}${separator}${formattedSignature.value}`;
});

watch(
  () => props.signaturePosition,
  newValue => {
    signaturePosition.value = newValue;
  },
  { immediate: true }
);

watch(
  () => props.signatureSeparator,
  newValue => {
    signatureSeparator.value = newValue;
  },
  { immediate: true }
);

watch(
  () => props.messageSignature ?? '',
  newValue => {
    signature.value = newValue;
  },
  { immediate: true }
);

const updateSignature = () => {
  emit(
    'updateSignature',
    signature.value,
    signaturePosition.value,
    signatureSeparator.value
  );
};

const handlePositionChange = value => {
  signaturePosition.value = value;
  emit('updateSignature', signature.value, value, signatureSeparator.value);
};

const handleSeparatorChange = value => {
  signatureSeparator.value = value;
  emit('updateSignature', signature.value, signaturePosition.value, value);
};
</script>

<template>
  <form class="flex flex-col gap-6" @submit.prevent="updateSignature()">
    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
      <div class="flex flex-col gap-2">
        <label
          for="signaturePosition"
          class="text-sm font-medium text-n-slate-12"
        >
          {{
            t(
              'PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.SIGNATURE_POSITION.LABEL'
            )
          }}
        </label>
        <select
          id="signaturePosition"
          v-model="signaturePosition"
          name="signaturePosition"
          class="block w-full px-3 py-2 pr-6 mb-0 shadow-sm appearance-none rounded-xl select-caret leading-6 bg-white dark:bg-n-slate-3 border border-n-slate-3 dark:border-n-slate-7"
          @change="handlePositionChange($event.target.value)"
        >
          <option
            v-for="option in positionOptions"
            :key="option.value"
            :value="option.value"
            :selected="option.value === signaturePosition"
          >
            {{ option.label }}
          </option>
        </select>
      </div>
      <div class="flex flex-col gap-2">
        <label
          for="signatureSeparator"
          class="text-sm font-medium text-n-slate-12"
        >
          {{
            t(
              'PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.SIGNATURE_SEPARATOR.LABEL'
            )
          }}
        </label>
        <select
          id="signatureSeparator"
          v-model="signatureSeparator"
          name="signatureSeparator"
          class="block w-full px-3 py-2 pr-6 mb-0 shadow-sm appearance-none rounded-xl select-caret leading-6 bg-white dark:bg-n-slate-3 border border-n-slate-3 dark:border-n-slate-7"
          @change="handleSeparatorChange($event.target.value)"
        >
          <option
            v-for="option in separatorOptions"
            :key="option.value"
            :value="option.value"
            :selected="option.value === signatureSeparator"
          >
            {{ option.label }}
          </option>
        </select>
      </div>
    </div>
    <WootMessageEditor
      id="message-signature-input"
      v-model="signature"
      class="message-editor h-[10rem] !px-3"
      is-format-mode
      :placeholder="$t('PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE.PLACEHOLDER')"
      channel-type="Context::MessageSignature"
      :enable-suggestions="false"
      show-image-resize-toolbar
    />
    <div
      class="flex flex-col gap-3 p-4 bg-n-slate-1 dark:bg-n-slate-2 rounded-lg border border-n-slate-4 dark:border-n-slate-8"
    >
      <div class="flex items-center gap-2">
        <fluent-icon icon="info" size="16" class="text-n-slate-11" />
        <h3 class="text-sm font-medium text-n-slate-12 m-0">
          {{
            $t('PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.PREVIEW.TITLE')
          }}
        </h3>
      </div>
      <div
        class="bg-white dark:bg-n-slate-3 rounded-md p-3 border border-n-slate-3 dark:border-n-slate-7"
      >
        <div
          v-if="messagePreview"
          v-dompurify-html="messagePreview"
          class="message-preview text-sm text-n-slate-12 [&>p]:mb-2 [&>p:last-child]:mb-0"
        />
        <div v-else class="text-sm text-n-slate-10 italic">
          {{
            $t('PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.PREVIEW.EMPTY')
          }}
        </div>
      </div>
      <p class="text-xs text-n-slate-11 m-0">
        {{ $t('PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.PREVIEW.NOTE') }}
      </p>
    </div>
    <div>
      <NextButton
        type="submit"
        :label="$t('PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.BTN_TEXT')"
      />
    </div>
  </form>
</template>
