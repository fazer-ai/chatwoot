<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const props = defineProps({
  filters: { type: Object, required: true },
  inboxes: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:filters', 'apply']);
const { t } = useI18n();

const updateFilter = (key, value) => {
  emit('update:filters', { ...props.filters, [key]: value });
};

const temperatureOptions = computed(() => [
  { value: '', label: t('KANBAN.FILTERS.ALL_TEMPERATURES') },
  { value: 'quente', label: t('KANBAN.TEMPERATURE.QUENTE') },
  { value: 'morno', label: t('KANBAN.TEMPERATURE.MORNO') },
  { value: 'frio', label: t('KANBAN.TEMPERATURE.FRIO') },
]);
const scoreOptions = computed(() => [
  { value: '', label: t('KANBAN.FILTERS.ALL_SCORES') },
  { value: 'alto', label: t('KANBAN.FILTERS.SCORE_HIGH') },
  { value: 'medio', label: t('KANBAN.FILTERS.SCORE_MEDIUM') },
  { value: 'baixo', label: t('KANBAN.FILTERS.SCORE_LOW') },
]);
const inboxOptions = computed(() => [
  { value: '', label: t('KANBAN.FILTERS.ALL_INBOXES') },
  ...props.inboxes.map(inbox => ({ value: inbox.id, label: inbox.name })),
]);
const hasFilters = computed(() => Object.values(props.filters).some(Boolean));

const clearFilters = () => {
  emit('update:filters', {
    search: '',
    temperatura: '',
    score: '',
    inbox_id: '',
  });
  emit('apply');
};
</script>

<template>
  <form
    class="flex flex-wrap gap-2 items-center px-4 py-3 border-b bg-n-solid-1 border-n-weak"
    @submit.prevent="emit('apply')"
  >
    <Input
      :model-value="filters.search"
      class="w-full sm:w-72"
      size="sm"
      :placeholder="t('KANBAN.FILTERS.SEARCH')"
      @update:model-value="updateFilter('search', $event)"
    />
    <Select
      :model-value="filters.temperatura"
      :options="temperatureOptions"
      :aria-label="t('KANBAN.FILTERS.TEMPERATURE')"
      @update:model-value="updateFilter('temperatura', $event)"
    />
    <Select
      :model-value="filters.score"
      :options="scoreOptions"
      :aria-label="t('KANBAN.FILTERS.SCORE')"
      @update:model-value="updateFilter('score', $event)"
    />
    <Select
      :model-value="filters.inbox_id"
      :options="inboxOptions"
      :aria-label="t('KANBAN.FILTERS.INBOX')"
      @update:model-value="updateFilter('inbox_id', $event)"
    />
    <Button solid blue sm type="submit">{{ t('KANBAN.FILTERS.APPLY') }}</Button>
    <Button
      v-if="hasFilters"
      ghost
      slate
      sm
      type="button"
      @click="clearFilters"
    >
      {{ t('KANBAN.FILTERS.CLEAR') }}
    </Button>
  </form>
</template>
