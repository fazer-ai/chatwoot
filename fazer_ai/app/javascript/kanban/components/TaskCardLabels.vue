<script setup>
import { ref, computed, watch, onMounted, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

const props = defineProps({
  taskLabels: {
    type: Array,
    default: () => [],
  },
});

const { t } = useI18n();
const accountLabels = useMapGetter('labels/getLabels');

const activeLabels = computed(() => {
  return accountLabels.value.filter(({ title }) =>
    props.taskLabels.includes(title)
  );
});

const showAllLabels = ref(false);
const showExpandLabelButton = ref(false);
const labelPosition = ref(-1);
const labelContainer = ref(null);

const computeVisibleLabelPosition = () => {
  if (!labelContainer.value) {
    return;
  }

  const labels = Array.from(labelContainer.value.querySelectorAll('.label'));
  let labelOffset = 0;
  showExpandLabelButton.value = false;
  labels.forEach((label, index) => {
    labelOffset += label.offsetWidth + 8;

    if (labelOffset < labelContainer.value.clientWidth) {
      labelPosition.value = index;
    } else {
      showExpandLabelButton.value = labels.length > 1;
    }
  });
};

watch(activeLabels, () => {
  nextTick(() => computeVisibleLabelPosition());
});

onMounted(() => {
  computeVisibleLabelPosition();
});

const onShowLabels = e => {
  e.stopPropagation();
  e.preventDefault();
  showAllLabels.value = !showAllLabels.value;
  nextTick(() => computeVisibleLabelPosition());
};
</script>

<template>
  <div ref="labelContainer" v-resize="computeVisibleLabelPosition">
    <div
      class="flex items-center flex-shrink min-w-0 gap-1.5"
      :class="{ 'h-auto overflow-visible flex-row flex-wrap': showAllLabels }"
    >
      <div
        v-for="(label, index) in activeLabels"
        :key="label.id"
        class="label flex items-center gap-1 min-w-0 max-w-full px-2 py-0.5 rounded bg-n-alpha-2"
        :class="{
          'invisible absolute': !showAllLabels && index > labelPosition,
        }"
      >
        <div
          :style="{ backgroundColor: label.color }"
          class="size-1.5 rounded-full flex-shrink-0"
        />
        <span
          class="text-xs text-n-slate-11 whitespace-nowrap truncate max-w-24"
          :title="label.title"
        >
          {{ label.title }}
        </span>
      </div>
      <button
        v-if="showExpandLabelButton"
        :title="
          showAllLabels
            ? t('CONVERSATION.CARD.HIDE_LABELS')
            : t('CONVERSATION.CARD.SHOW_LABELS')
        "
        class="h-5 py-0 px-0.5 flex-shrink-0 text-n-slate-11 hover:text-n-slate-12"
        @click="onShowLabels"
      >
        <span
          :class="
            showAllLabels
              ? 'i-lucide-chevron-left'
              : 'i-lucide-chevron-right rtl:rotate-180'
          "
          class="w-3 h-3"
        />
      </button>
    </div>
  </div>
</template>
