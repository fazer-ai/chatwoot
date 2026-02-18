<script setup>
import { ref, computed } from 'vue';
import { OnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

const props = defineProps({
  type: {
    type: String,
    default: 'edit',
    validator: value => ['alert', 'edit'].includes(value),
  },
  title: {
    type: String,
    default: '',
  },
  description: {
    type: String,
    default: '',
  },
  cancelButtonLabel: {
    type: String,
    default: '',
  },
  confirmButtonLabel: {
    type: String,
    default: '',
  },
  disableConfirmButton: {
    type: Boolean,
    default: false,
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  showCancelButton: {
    type: Boolean,
    default: true,
  },
  showConfirmButton: {
    type: Boolean,
    default: true,
  },
  overflowYAuto: {
    type: Boolean,
    default: false,
  },
  width: {
    type: String,
    default: 'lg',
    validator: value => ['3xl', '2xl', 'xl', 'lg', 'md', 'sm'].includes(value),
  },
  position: {
    type: String,
    default: 'center',
    validator: value => ['center', 'top'].includes(value),
  },
  ignoreClickOutside: {
    type: Boolean,
    default: false,
  },
  id: {
    type: String,
    default: null,
  },
});

const emit = defineEmits(['confirm', 'close', 'clickOutside']);

const { t } = useI18n();

const dialogRef = ref(null);
const dialogContentRef = ref(null);
const isOpen = ref(false);

const maxWidthClass = computed(() => {
  const classesMap = {
    '3xl': 'max-w-3xl',
    '2xl': 'max-w-2xl',
    xl: 'max-w-xl',
    lg: 'max-w-lg',
    md: 'max-w-md',
    sm: 'max-w-sm',
  };

  return classesMap[props.width] ?? 'max-w-md';
});

const positionClass = computed(() =>
  props.position === 'top' ? 'dialog-position-top' : ''
);

const open = () => {
  isOpen.value = true;
  dialogRef.value?.showModal();
};

const close = () => {
  emit('close');
  dialogRef.value?.close();
  isOpen.value = false;
};

const onClickOutside = () => {
  if (props.ignoreClickOutside) {
    emit('clickOutside');
    return;
  }
  close();
};

const confirm = () => {
  emit('confirm');
};

defineExpose({ open, close, dialogRef });
</script>

<template>
  <TeleportWithDirection to="body">
    <dialog
      :id="id"
      ref="dialogRef"
      class="transition-all duration-300 ease-in-out"
      :class="[
        positionClass,
        overflowYAuto
          ? 'dialog-fullscreen-scroll fixed inset-0 w-full h-full max-w-none max-h-none bg-transparent shadow-none p-4 overflow-y-auto'
          : ['w-full shadow-xl rounded-xl overflow-visible', maxWidthClass],
      ]"
      @close="close"
    >
      <OnClickOutside
        :class="[overflowYAuto ? ['w-full', maxWidthClass] : '']"
        @trigger="onClickOutside"
      >
        <form
          ref="dialogContentRef"
          class="flex flex-col w-full h-auto gap-6 p-6 overflow-visible text-start align-middle transition-all duration-300 ease-in-out transform bg-n-alpha-3 backdrop-blur-[100px] shadow-xl rounded-xl"
          @submit.prevent="confirm"
          @click.stop
        >
          <div v-if="title || description" class="flex flex-col gap-2">
            <div class="flex items-start justify-between gap-4">
              <h3
                class="text-base font-medium leading-6 text-n-slate-12 break-words min-w-0 flex-1"
              >
                {{ title }}
              </h3>
              <slot name="header-actions" />
            </div>
            <slot name="description">
              <p
                v-if="description"
                class="mb-0 text-sm text-n-slate-11 break-words"
              >
                {{ description }}
              </p>
            </slot>
          </div>
          <slot v-if="isOpen" />
          <!-- Dialog content will be injected here -->
          <slot name="footer">
            <div
              v-if="showCancelButton || showConfirmButton"
              class="flex items-center justify-between w-full gap-3"
            >
              <Button
                v-if="showCancelButton"
                variant="faded"
                color="slate"
                :label="cancelButtonLabel || t('DIALOG.BUTTONS.CANCEL')"
                class="w-full"
                type="button"
                @click="close"
              />
              <Button
                v-if="showConfirmButton"
                :color="type === 'edit' ? 'blue' : 'ruby'"
                :label="confirmButtonLabel || t('DIALOG.BUTTONS.CONFIRM')"
                class="w-full"
                :is-loading="isLoading"
                :disabled="disableConfirmButton || isLoading"
                type="submit"
              />
            </div>
          </slot>
        </form>
      </OnClickOutside>
    </dialog>
  </TeleportWithDirection>
</template>

<style scoped>
dialog::backdrop {
  @apply bg-n-alpha-black1 backdrop-blur-[4px];
}

.dialog-position-top {
  margin-top: clamp(2rem, 5vh, 5rem);
  margin-bottom: auto;
}

dialog.dialog-fullscreen-scroll[open] {
  display: grid;
  place-items: center;
}
</style>
