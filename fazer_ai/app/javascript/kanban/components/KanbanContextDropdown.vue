<script setup>
import { ref } from 'vue';
import ContextMenu from 'dashboard/components/ui/ContextMenu.vue';
import MultiselectDropdownItems from 'shared/components/ui/MultiselectDropdownItems.vue';

const props = defineProps({
  options: {
    type: Array,
    default: () => [],
  },
  selectedItem: {
    type: Object,
    default: null,
  },
  maxHeight: {
    type: String,
    default: '12rem',
  },
  hasThumbnail: {
    type: Boolean,
    default: true,
  },
  hideSearch: {
    type: Boolean,
    default: true,
  },
  teleportTo: {
    type: String,
    default: 'body',
  },
});

const emit = defineEmits(['select', 'close', 'open']);

const showMenu = ref(false);
const menuPosition = ref({ x: 0, y: 0 });
const triggerElement = ref(null);

const close = () => {
  showMenu.value = false;
  emit('close');
};

const open = event => {
  triggerElement.value = event.currentTarget || event.target;

  if (showMenu.value) {
    close();
    return;
  }

  const rect = triggerElement.value.getBoundingClientRect();
  menuPosition.value = { x: rect.left, y: rect.bottom + 8 };
  showMenu.value = true;
  emit('open');
};

const onSelect = item => {
  emit('select', item);
  close();
};
</script>

<template>
  <slot name="trigger" :open="open" :is-open="showMenu" />

  <ContextMenu
    v-if="showMenu"
    :x="menuPosition.x"
    :y="menuPosition.y"
    :ignore-element="triggerElement"
    :to="teleportTo"
    @close="close"
  >
    <div
      class="w-48 overflow-hidden rounded-lg bg-n-alpha-3 backdrop-blur-[100px] border border-n-strong dark:border-n-strong p-2 shadow-lg cursor-default"
    >
      <MultiselectDropdownItems
        :options="options"
        :selected-items="selectedItem ? [selectedItem] : []"
        :hide-search="hideSearch"
        :max-height="maxHeight"
        :has-thumbnail="hasThumbnail"
        @select="onSelect"
      />
    </div>
  </ContextMenu>
</template>
