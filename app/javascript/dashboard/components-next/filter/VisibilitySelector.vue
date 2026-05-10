<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  modelValue: {
    type: String,
    default: 'personal',
  },
  i18nPrefix: {
    type: String,
    required: true,
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const label = computed(() => t(`${props.i18nPrefix}.LABEL`));
const globalLabel = computed(() => t(`${props.i18nPrefix}.GLOBAL.LABEL`));
const globalDescription = computed(() =>
  t(`${props.i18nPrefix}.GLOBAL.DESCRIPTION`)
);
const personalLabel = computed(() => t(`${props.i18nPrefix}.PERSONAL.LABEL`));
const personalDescription = computed(() =>
  t(`${props.i18nPrefix}.PERSONAL.DESCRIPTION`)
);

const isActive = key =>
  props.modelValue === key
    ? 'bg-n-blue-2 dark:bg-n-blue-1 border-n-blue-3 dark:border-n-blue-4'
    : 'bg-white dark:bg-n-solid-2 border-n-weak dark:border-n-strong';

const select = value => emit('update:modelValue', value);
</script>

<template>
  <div>
    <p class="block m-0 text-sm font-medium leading-[1.8] text-n-slate-12">
      {{ label }}
    </p>
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-3">
      <button
        type="button"
        class="p-2 relative rounded-md border border-solid justify-between items-start gap-2 flex flex-col text-start cursor-pointer"
        :class="isActive('global')"
        :aria-pressed="modelValue === 'global'"
        @click.prevent="select('global')"
      >
        <div class="flex items-center gap-2 min-w-0 justify-between w-full">
          <p class="block m-0 text-heading-3 text-n-slate-12 line-clamp-1">
            {{ globalLabel }}
          </p>
          <Icon
            v-if="modelValue === 'global'"
            icon="i-lucide-circle-check-big"
            class="text-n-brand size-4"
          />
        </div>
        <p class="text-n-slate-11 text-label-small">
          {{ globalDescription }}
        </p>
      </button>
      <button
        type="button"
        class="p-2 relative rounded-md border border-solid justify-between items-start gap-2 flex flex-col text-start cursor-pointer"
        :class="isActive('personal')"
        :aria-pressed="modelValue === 'personal'"
        @click.prevent="select('personal')"
      >
        <div class="flex items-center gap-2 min-w-0 justify-between w-full">
          <p class="block m-0 text-heading-3 text-n-slate-12 line-clamp-1">
            {{ personalLabel }}
          </p>
          <Icon
            v-if="modelValue === 'personal'"
            icon="i-lucide-circle-check-big"
            class="text-n-brand size-4"
          />
        </div>
        <p class="text-n-slate-11 text-label-small">
          {{ personalDescription }}
        </p>
      </button>
    </div>
  </div>
</template>
