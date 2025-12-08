<script setup>
import { ref, toRef, computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  activeSort: {
    type: String,
    default: 'updated_at',
  },
  activeOrdering: {
    type: String,
    default: 'desc',
  },
});

const emit = defineEmits(['update:sort']);

const { t } = useI18n();

const isMenuOpen = ref(false);

const sortMenus = computed(() => [
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.SORT_BY.OPTIONS.LAST_ACTIVITY'),
    value: 'updated_at',
  },
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.SORT_BY.OPTIONS.NAME'),
    value: 'name',
  },
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.SORT_BY.OPTIONS.CREATED_AT'),
    value: 'created_at',
  },
]);

const orderingMenus = computed(() => [
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.ORDER.OPTIONS.ASCENDING'),
    value: 'asc',
  },
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.ORDER.OPTIONS.DESCENDING'),
    value: 'desc',
  },
]);

const activeSort = toRef(props, 'activeSort');
const activeOrdering = toRef(props, 'activeOrdering');

const handleSortChange = value => {
  emit('update:sort', { sort: value, order: props.activeOrdering });
  isMenuOpen.value = false;
};

const handleOrderChange = value => {
  emit('update:sort', { sort: props.activeSort, order: value });
  isMenuOpen.value = false;
};
</script>

<template>
  <div v-on-clickaway="() => (isMenuOpen = false)" class="relative">
    <Button
      icon="i-lucide-arrow-down-up"
      color="slate"
      size="sm"
      variant="ghost"
      class="!px-2"
      @click="isMenuOpen = !isMenuOpen"
    />
    <div
      v-if="isMenuOpen"
      class="absolute right-0 top-full mt-1 z-20 w-56 flex flex-col gap-1 bg-n-alpha-3 backdrop-blur-[100px] p-1 shadow-lg rounded-lg border border-n-weak dark:border-n-strong/50"
    >
      <div class="px-4 py-2 text-xs font-medium text-n-slate-11 uppercase">
        {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.SORT_BY.LABEL') }}
      </div>
      <Button
        v-for="menu in sortMenus"
        :key="menu.value"
        :label="menu.label"
        :icon="activeSort === menu.value ? 'i-lucide-check' : ''"
        size="sm"
        variant="ghost"
        color="slate"
        trailing-icon
        class="!justify-end !px-2.5 !h-7"
        :class="{ '!bg-n-alpha-2': activeSort === menu.value }"
        @click="handleSortChange(menu.value)"
      />
      <div class="border-t border-n-slate-3 my-1" />
      <div class="px-4 py-2 text-xs font-medium text-n-slate-11 uppercase">
        {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.ORDER.LABEL') }}
      </div>
      <Button
        v-for="menu in orderingMenus"
        :key="menu.value"
        :label="menu.label"
        :icon="activeOrdering === menu.value ? 'i-lucide-check' : ''"
        size="sm"
        variant="ghost"
        color="slate"
        trailing-icon
        class="!justify-end !px-2.5 !h-7"
        :class="{ '!bg-n-alpha-2': activeOrdering === menu.value }"
        @click="handleOrderChange(menu.value)"
      />
    </div>
  </div>
</template>
