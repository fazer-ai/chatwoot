<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import WootMessageEditor from 'dashboard/components/widgets/WootWriter/Editor.vue';
import { MESSAGE_SIGNATURE_EDITOR_MENU_OPTIONS } from 'dashboard/constants/editor';
import FormButton from 'v3/components/Form/Button.vue';
import Switch from 'v3/components/Form/Switch.vue';

const props = defineProps({
  messageSignature: {
    type: String,
    default: '',
  },
  signaturePosition: {
    type: String,
    default: 'top', // NOTE: 'top' or 'bottom'
  },
  signatureSeparator: {
    type: String,
    default: 'blank', // NOTE: 'blank' or '--'
  },
});

const emit = defineEmits(['updateSignature']);

const { t } = useI18n();

const customEditorMenuList = MESSAGE_SIGNATURE_EDITOR_MENU_OPTIONS;
const signature = ref(props.messageSignature);
const signaturePosition = ref(props.signaturePosition === 'top');
const signatureSeparator = ref(props.signatureSeparator === 'blank');

watch(
  () => props.signaturePosition,
  newValue => {
    signaturePosition.value = newValue === 'top';
  }
);

watch(
  () => props.signatureSeparator,
  newValue => {
    signatureSeparator.value = newValue === 'blank';
  }
);

watch(
  () => props.messageSignature ?? '',
  newValue => {
    signature.value = newValue;
  }
);

const updateSignature = () => {
  const position = signaturePosition.value ? 'top' : 'bottom';
  const separator = signatureSeparator.value ? 'blank' : '--';
  emit('updateSignature', signature.value, position, separator);
};

const handlePositionChange = value => {
  signaturePosition.value = value;
  const position = value ? 'top' : 'bottom';
  const separator = signatureSeparator.value ? 'blank' : '--';
  emit('updateSignature', signature.value, position, separator);
};

const handleSeparatorChange = value => {
  signatureSeparator.value = value;
  const position = signaturePosition.value ? 'top' : 'bottom';
  const separator = value ? 'blank' : '--';
  emit('updateSignature', signature.value, position, separator);
};
</script>

<template>
  <form class="flex flex-col gap-6" @submit.prevent="updateSignature()">
    <div class="flex items-center justify-between">
      <div class="w-1/4 flex flex-col gap-2">
        <label>
          {{
            $t(
              'PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.SIGNATURE_POSITION.LABEL'
            )
          }}
        </label>
        <label>
          {{
            $t(
              'PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.SIGNATURE_SEPARATOR.LABEL'
            )
          }}
        </label>
      </div>
      <div class="w-3/4 flex flex-col gap-2 justify-between">
        <div class="flex items-center gap-2">
          <span class="w-2/5 text-sm text-right">
            {{
              t(
                'PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.SIGNATURE_POSITION.OPTIONS.BOTTOM'
              )
            }}
          </span>
          <Switch
            v-model="signaturePosition"
            class="w-1/5"
            @update:model-value="handlePositionChange"
          />
          <span class="w-2/5 text-sm">
            {{
              t(
                'PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.SIGNATURE_POSITION.OPTIONS.TOP'
              )
            }}
          </span>
        </div>
        <div class="flex items-center gap-2">
          <span class="w-2/5 text-sm text-right">
            {{
              t(
                'PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.SIGNATURE_SEPARATOR.OPTIONS.HORIZONTAL_LINE'
              )
            }}
          </span>
          <Switch
            v-model="signatureSeparator"
            class="w-1/5"
            @update:model-value="handleSeparatorChange"
          />
          <span class="w-2/5 text-sm">
            {{
              t(
                'PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.SIGNATURE_SEPARATOR.OPTIONS.BLANK'
              )
            }}
          </span>
        </div>
      </div>
    </div>
    <WootMessageEditor
      id="message-signature-input"
      v-model="signature"
      class="message-editor h-[10rem] !px-3"
      is-format-mode
      :placeholder="$t('PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE.PLACEHOLDER')"
      :enabled-menu-options="customEditorMenuList"
      :enable-suggestions="false"
      show-image-resize-toolbar
    />
    <FormButton
      type="submit"
      color-scheme="primary"
      variant="solid"
      size="large"
    >
      {{ $t('PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.BTN_TEXT') }}
    </FormButton>
  </form>
</template>
