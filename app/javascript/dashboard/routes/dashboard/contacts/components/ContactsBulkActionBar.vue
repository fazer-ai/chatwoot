<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import BulkSelectBar from 'dashboard/components-next/captain/assistant/BulkSelectBar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import BulkLabelActions from 'dashboard/components/widgets/conversation/conversationBulkActions/BulkLabelActions.vue';
import LabelActions from 'dashboard/components/widgets/conversation/conversationBulkActions/LabelActions.vue';
import Policy from 'dashboard/components/policy.vue';
import { vOnClickOutside } from '@vueuse/components';

const props = defineProps({
  visibleContactIds: {
    type: Array,
    default: () => [],
  },
  selectedContactIds: {
    type: Array,
    default: () => [],
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'clearSelection',
  'assignLabels',
  'unassignLabels',
  'toggleAll',
  'deleteSelected',
]);

const { t } = useI18n();

const selectedCount = computed(() => props.selectedContactIds.length);
const totalVisibleContacts = computed(() => props.visibleContactIds.length);
const showUnassignLabelSelector = ref(false);

const selectAllLabel = computed(() => {
  if (!totalVisibleContacts.value) {
    return '';
  }

  return t('CONTACTS_BULK_ACTIONS.SELECT_ALL', {
    count: totalVisibleContacts.value,
  });
});

const selectedCountLabel = computed(() =>
  t('CONTACTS_BULK_ACTIONS.SELECTED_COUNT', {
    count: selectedCount.value,
  })
);

const allItems = computed(() =>
  props.visibleContactIds.map(id => ({
    id,
  }))
);

const selectionModel = computed({
  get: () => new Set(props.selectedContactIds),
  set: newSet => {
    if (!props.visibleContactIds.length) {
      emit('toggleAll', false);
      return;
    }

    const shouldSelectAll = props.visibleContactIds.every(id => newSet.has(id));
    emit('toggleAll', shouldSelectAll);
  },
});

const toggleUnassignLabelSelector = () => {
  if (!selectedCount.value || props.isLoading) return;
  showUnassignLabelSelector.value = !showUnassignLabelSelector.value;
};

const closeUnassignLabelSelector = () => {
  showUnassignLabelSelector.value = false;
};

const handleAssignLabels = labels => {
  emit('assignLabels', labels);
};

const handleUnassignLabels = labels => {
  emit('unassignLabels', labels);
  closeUnassignLabelSelector();
};
</script>

<template>
  <div
    class="sticky top-0 z-10 bg-gradient-to-b from-n-surface-1 from-90% to-transparent pt-1 pb-2"
  >
    <BulkSelectBar
      v-model="selectionModel"
      :all-items="allItems"
      :select-all-label="selectAllLabel"
      :selected-count-label="selectedCountLabel"
      class="py-2 ltr:!pr-3 rtl:!pl-3 justify-between"
    >
      <template #primaryActions>
        <Button
          sm
          ghost
          slate
          :label="t('CONTACTS_BULK_ACTIONS.CLEAR_SELECTION')"
          class="!px-1"
          @click="emit('clearSelection')"
        />
      </template>
      <template #actions>
        <div class="flex items-center gap-2 ml-auto">
          <BulkLabelActions
            type="contact"
            :is-loading="isLoading"
            :disabled="!selectedCount"
            @assign="handleAssignLabels"
          />
          <!-- Auris: unassign labels stays as a separate popover; upstream's
               BulkLabelActions only supports assign. -->
          <div
            v-on-click-outside="closeUnassignLabelSelector"
            class="relative flex items-center"
          >
            <Button
              sm
              faded
              slate
              icon="i-lucide-tag"
              :label="t('CONTACTS_BULK_ACTIONS.UNASSIGN_LABELS')"
              :disabled="!selectedCount || isLoading"
              :is-loading="isLoading"
              class="[&>span:nth-child(2)]:hidden sm:[&>span:nth-child(2)]:inline w-fit"
              @click="toggleUnassignLabelSelector"
            />
            <transition
              enter-active-class="transition ease-out duration-100"
              enter-from-class="transform opacity-0 scale-95"
              enter-to-class="transform opacity-100 scale-100"
              leave-active-class="transition ease-in duration-75"
              leave-from-class="transform opacity-100 scale-100"
              leave-to-class="transform opacity-0 scale-95"
            >
              <LabelActions
                v-if="showUnassignLabelSelector"
                mode="unassign"
                class="[&>.triangle]:!hidden [&>div>button]:!hidden ltr:!right-0 rtl:!left-0 top-8 mt-0.5"
                @unassign="handleUnassignLabels"
              />
            </transition>
          </div>
          <div class="w-px h-3 bg-n-weak rounded-lg" />
          <Policy :permissions="['administrator']">
            <Button
              v-tooltip.bottom="t('CONTACTS_BULK_ACTIONS.DELETE_CONTACTS')"
              sm
              ghost
              ruby
              icon="i-lucide-trash"
              :label="t('CONTACTS_BULK_ACTIONS.DELETE_CONTACTS')"
              :aria-label="t('CONTACTS_BULK_ACTIONS.DELETE_CONTACTS')"
              :disabled="!selectedCount || isLoading"
              :is-loading="isLoading"
              class="!px-2 [&>span:nth-child(2)]:hidden md:[&>span:nth-child(2)]:inline-flex"
              @click="emit('deleteSelected')"
            />
          </Policy>
        </div>
      </template>
    </BulkSelectBar>
  </div>
</template>
