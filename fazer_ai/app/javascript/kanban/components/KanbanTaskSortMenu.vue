<script setup>
import { ref, toRef, computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

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
    label: t('KANBAN.SORT.OPTIONS.MANUAL'),
    value: 'position',
    icon: 'i-lucide-arrow-down-up',
  },
  {
    label: t('KANBAN.SORT.OPTIONS.NAME'),
    value: 'title',
    icon: 'i-lucide-type',
  },
  {
    label: t('KANBAN.SORT.OPTIONS.LAST_ACTIVITY'),
    value: 'updated_at',
    icon: 'i-lucide-clock',
  },
  {
    label: t('KANBAN.SORT.OPTIONS.CREATED_AT'),
    value: 'created_at',
    icon: 'i-lucide-calendar',
  },
  {
    label: t('KANBAN.SORT.OPTIONS.PRIORITY'),
    value: 'priority',
    icon: 'i-lucide-flag',
  },
  {
    label: t('KANBAN.SORT.OPTIONS.DUE_DATE'),
    value: 'due_date',
    icon: 'i-lucide-calendar-clock',
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

const activeSortIcon = computed(() => {
  const active = sortMenus.value.find(menu => menu.value === activeSort.value);
  return active ? active.icon : 'i-lucide-arrow-down-up';
});

const activeDirectionIcon = computed(() => {
  return activeOrdering.value === 'asc'
    ? 'i-lucide-arrow-up'
    : 'i-lucide-arrow-down';
});
</script>

<template>
  <div v-on-clickaway="() => (isMenuOpen = false)" class="relative">
    <Button
      :icon="activeSortIcon"
      color="slate"
      size="sm"
      variant="ghost"
      class="!px-2 gap-1"
      @click="isMenuOpen = !isMenuOpen"
    >
      <Icon
        v-if="activeSort !== 'position'"
        :icon="activeDirectionIcon"
        class="w-4 h-4 text-n-slate-11"
      />
    </Button>
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
