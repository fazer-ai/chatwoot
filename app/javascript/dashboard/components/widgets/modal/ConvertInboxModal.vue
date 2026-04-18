<script setup>
import { computed, ref } from 'vue';
import { required } from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import Modal from '../../Modal.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  inboxName: { type: String, required: true },
  currentProvider: { type: String, default: '' },
});

const emit = defineEmits(['onClose', 'onConfirm', 'update:show']);

const value = ref('');

const validations = {
  value: {
    required,
    isEqual(input) {
      return (input || '').trim() === (props.inboxName || '').trim();
    },
  },
};

const v$ = useVuelidate(validations, { value });

const localShow = computed({
  get: () => props.show,
  set: next => emit('update:show', next),
});

const closeModal = () => {
  value.value = '';
  v$.value.$reset();
  localShow.value = false;
  emit('onClose');
};

const onConfirm = () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;
  emit('onConfirm');
};
</script>

<template>
  <Modal v-model:show="localShow" :on-close="closeModal">
    <woot-modal-header :header-title="$t('INBOX_MGMT.CONVERT.CONFIRM.TITLE')" />
    <div class="px-8 pt-4">
      <p class="text-sm leading-5 text-n-slate-11">
        {{
          $t('INBOX_MGMT.CONVERT.CONFIRM.INTRO', {
            inboxName: inboxName,
            currentProvider: currentProvider,
          })
        }}
      </p>
      <ul
        class="pl-5 mt-4 space-y-1 text-sm list-disc leading-5 text-n-slate-11"
      >
        <li>
          {{
            $t('INBOX_MGMT.CONVERT.CONFIRM.EFFECT_DISCONNECT', {
              currentProvider: currentProvider,
            })
          }}
        </li>
        <li>{{ $t('INBOX_MGMT.CONVERT.CONFIRM.EFFECT_TEMPLATES') }}</li>
        <li>{{ $t('INBOX_MGMT.CONVERT.CONFIRM.EFFECT_CONNECTION') }}</li>
        <li>{{ $t('INBOX_MGMT.CONVERT.CONFIRM.EFFECT_PRESERVED') }}</li>
        <li>{{ $t('INBOX_MGMT.CONVERT.CONFIRM.EFFECT_IDENTITY') }}</li>
      </ul>
      <p class="mt-4 text-sm leading-5 text-n-slate-11">
        {{ $t('INBOX_MGMT.CONVERT.CONFIRM.CONFIRM_PROMPT') }}
      </p>
    </div>
    <form class="px-8 pb-6" @submit.prevent="onConfirm">
      <woot-input
        v-model="value"
        type="text"
        :class="{ error: v$.value.$error }"
        :placeholder="
          $t('INBOX_MGMT.CONVERT.CONFIRM.PLACE_HOLDER', {
            inboxName: inboxName,
          })
        "
        @blur="v$.value.$touch"
      />
      <div class="flex items-center justify-end gap-2">
        <NextButton
          faded
          slate
          type="reset"
          :label="$t('INBOX_MGMT.CONVERT.CONFIRM.CANCEL')"
          @click.prevent="closeModal"
        />
        <NextButton
          ruby
          type="submit"
          :label="$t('INBOX_MGMT.CONVERT.CONFIRM.CONTINUE')"
          :disabled="v$.value.$invalid"
        />
      </div>
    </form>
  </Modal>
</template>
