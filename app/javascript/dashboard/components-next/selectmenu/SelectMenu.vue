<script setup>
import { ref, computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  options: {
    type: Array,
    required: true,
  },
  modelValue: {
    type: String,
    required: true,
  },
  label: {
    type: String,
    required: true,
  },
  thumbnail: {
    type: String,
    default: null,
  },
  showAvatar: {
    type: Boolean,
    default: false,
  },
  icon: {
    type: String,
    default: null,
  },
  subMenuPosition: {
    type: String,
    default: 'right',
    validator: value => {
      return ['right', 'left', 'bottom'].includes(value);
    },
  },
  maxWidth: {
    type: String,
    default: 'max-w-40',
  },
  hideLabel: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update:modelValue']);

const isOpen = ref(false);

const labelValue = computed(() => props.label);

const toggleMenu = () => {
  isOpen.value = !isOpen.value;
};

const handleSelect = value => {
  emit('update:modelValue', value);
  isOpen.value = false;
};
</script>

<template>
  <div
    v-on-clickaway="() => (isOpen = false)"
    class="relative flex flex-col gap-1 w-fit"
  >
    <Button
      icon="i-lucide-chevron-down"
      size="sm"
      trailing-icon
      color="slate"
      variant="faded"
      class="!w-fit"
      :class="[maxWidth, { 'dark:!bg-n-alpha-2 !bg-n-slate-9/20': isOpen }]"
      @click="toggleMenu"
    >
      <div class="flex items-center gap-2 min-w-0">
        <Avatar
          v-if="showAvatar || thumbnail || icon"
          :src="thumbnail"
          :name="labelValue"
          :icon-name="icon"
          :size="16"
          class="flex-shrink-0"
        />
        <span v-if="!hideLabel" class="truncate">{{ labelValue }}</span>
      </div>
    </Button>
    <div
      v-if="isOpen"
      class="absolute select-none max-w-64 flex flex-col gap-1 bg-n-alpha-3 backdrop-blur-[100px] p-1 top-0 shadow-lg z-40 rounded-lg border border-n-weak dark:border-n-strong/50"
      :class="{
        'ltr:left-full rtl:right-full ltr:ml-1 rtl:mr-1':
          subMenuPosition === 'right',
        'ltr:right-full rtl:left-full ltr:mr-1 rtl:ml-1':
          subMenuPosition === 'left',
        'top-full mt-1 ltr:right-0 rtl:left-0': subMenuPosition === 'bottom',
      }"
    >
      <Button
        v-for="option in options"
        :key="option.value"
        :icon="option.value === modelValue ? 'i-lucide-check' : ''"
        size="sm"
        variant="ghost"
        color="slate"
        trailing-icon
        class="!justify-end !px-2.5 !h-7"
        :class="{ '!bg-n-alpha-2': option.value === modelValue }"
        @click="handleSelect(option.value)"
      >
        <div class="flex items-center gap-2 w-full min-w-0">
          <Avatar
            v-if="showAvatar || option.thumbnail || option.icon"
            :src="option.thumbnail"
            :name="option.label"
            :icon-name="option.icon"
            :size="16"
            class="flex-shrink-0"
          />
          <span class="truncate flex-grow text-left">{{ option.label }}</span>
          <span
            v-if="option.count !== undefined && option.value !== modelValue"
            class="flex h-5 min-w-[1.25rem] items-center justify-center rounded-full bg-n-slate-3 px-1.5 text-xs font-medium text-n-slate-11"
          >
            {{ option.count }}
          </span>
        </div>
      </Button>
    </div>
  </div>
</template>
