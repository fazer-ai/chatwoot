<script setup>
import { computed } from 'vue';
import { Pie } from 'vue-chartjs';
import { Chart as ChartJS, Title, Tooltip, Legend, ArcElement } from 'chart.js';

defineProps({
  collection: {
    type: Object,
    default: () => ({}),
  },
});

ChartJS.register(Title, Tooltip, Legend, ArcElement);

const fontFamily =
  'Inter,-apple-system,system-ui,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif';

const options = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    legend: {
      position: 'bottom',
      labels: { font: { family: fontFamily } },
    },
    tooltip: {
      callbacks: {
        label(ctx) {
          const value = ctx.parsed;
          const total = ctx.dataset.data.reduce((a, b) => a + b, 0);
          const pct = total === 0 ? 0 : Math.round((value / total) * 100);
          return `${ctx.label}: ${value} (${pct}%)`;
        },
      },
    },
  },
}));
</script>

<template>
  <Pie :data="collection" :options="options" />
</template>
