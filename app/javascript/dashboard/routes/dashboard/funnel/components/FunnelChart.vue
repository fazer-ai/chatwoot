<script setup>
import { computed } from 'vue';

const props = defineProps({
  stages: {
    type: Array,
    required: true,
  },
});

// SVG coordinate space. The viewBox is wider than tall to match the funnel
// reference; the actual rendered size is fluid via CSS. Stage labels sit
// above the funnel area, so we reserve `labelBand` vertical space at the top.
const VIEWBOX_WIDTH = 1200;
const VIEWBOX_HEIGHT = 480;
const LABEL_BAND = 120;
const FUNNEL_TOP = LABEL_BAND;
const FUNNEL_HEIGHT = VIEWBOX_HEIGHT - FUNNEL_TOP - 40;
const MIDPOINT = FUNNEL_TOP + FUNNEL_HEIGHT / 2;

// Max count anchors the funnel height at 100%. Using the largest stage (vs.
// always the first) keeps the chart honest when a downstream stage received
// more entries than the top — the bar reaches full height where the data
// actually peaks, so nothing visually exceeds the canvas.
const maxCount = computed(() => {
  const counts = props.stages.map(s => s.count || 0);
  return Math.max(1, ...counts);
});

const FILL_COLOR = '#3b82f6'; // tailwind blue-500 — neutral funnel fill

const stagePoints = computed(() => {
  const n = props.stages.length;
  if (n === 0) return [];

  return props.stages.map((stage, i) => {
    const count = stage.count || 0;
    const ratio = count / maxCount.value;
    const halfHeight = (ratio * FUNNEL_HEIGHT) / 2;
    // Spread stages evenly. With a single stage, center it.
    const x = n === 1 ? VIEWBOX_WIDTH / 2 : (i / (n - 1)) * VIEWBOX_WIDTH;
    return {
      x,
      topY: MIDPOINT - halfHeight,
      botY: MIDPOINT + halfHeight,
      count,
      stage,
    };
  });
});

// Cubic Bezier between consecutive stage points. Control points sit at the
// midpoint X to give the curve gentle S-shapes instead of straight slopes —
// matches the reference look without a chart dependency.
const funnelPath = computed(() => {
  const pts = stagePoints.value;
  if (pts.length === 0) return '';

  let d = `M ${pts[0].x.toFixed(2)} ${pts[0].topY.toFixed(2)}`;

  // Top edge left-to-right.
  for (let i = 1; i < pts.length; i += 1) {
    const prev = pts[i - 1];
    const curr = pts[i];
    const midX = (prev.x + curr.x) / 2;
    d += ` C ${midX.toFixed(2)} ${prev.topY.toFixed(2)}, ${midX.toFixed(2)} ${curr.topY.toFixed(2)}, ${curr.x.toFixed(2)} ${curr.topY.toFixed(2)}`;
  }

  // Close down on the right edge.
  d += ` L ${pts[pts.length - 1].x.toFixed(2)} ${pts[pts.length - 1].botY.toFixed(2)}`;

  // Bottom edge right-to-left, mirroring the top.
  for (let i = pts.length - 2; i >= 0; i -= 1) {
    const next = pts[i + 1];
    const curr = pts[i];
    const midX = (next.x + curr.x) / 2;
    d += ` C ${midX.toFixed(2)} ${next.botY.toFixed(2)}, ${midX.toFixed(2)} ${curr.botY.toFixed(2)}, ${curr.x.toFixed(2)} ${curr.botY.toFixed(2)}`;
  }

  d += ' Z';
  return d;
});

const labelsForStages = computed(() => {
  const pts = stagePoints.value;
  if (pts.length === 0) return [];

  // The denominator for the percentage is the largest count — keeps the
  // % monotonically <= 100% even when downstream stages overflow upstream.
  const denom = maxCount.value;

  return pts.map((pt, i) => {
    const pct = denom === 0 ? 0 : (pt.count / denom) * 100;
    // Anchor labels to the slice's x. End stages get tilted anchors so the
    // text doesn't spill outside the viewBox.
    let anchor = 'middle';
    if (i === 0) anchor = 'start';
    else if (i === pts.length - 1) anchor = 'end';
    return {
      key: pt.stage.id ?? pt.stage.name,
      x: pt.x,
      anchor,
      name: pt.stage.name,
      count: pt.count,
      pct,
    };
  });
});

const formatCount = value => Number(value || 0).toLocaleString();
const formatPct = value => `${Number(value).toFixed(1)}%`;
</script>

<template>
  <div class="w-full">
    <svg
      class="w-full h-auto"
      :viewBox="`0 0 ${VIEWBOX_WIDTH} ${VIEWBOX_HEIGHT}`"
      preserveAspectRatio="xMidYMid meet"
      role="img"
      :aria-label="$t('FUNNEL_CONVERSION_REPORTS.CHART_ARIA_LABEL')"
    >
      <defs>
        <linearGradient id="funnelGradient" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" :stop-color="FILL_COLOR" stop-opacity="0.55" />
          <stop offset="100%" :stop-color="FILL_COLOR" stop-opacity="0.95" />
        </linearGradient>
      </defs>

      <!-- Labels above each stage: name, count, pct -->
      <g v-for="label in labelsForStages" :key="label.key">
        <text
          :x="label.x"
          :y="32"
          :text-anchor="label.anchor"
          class="fill-n-slate-11 text-xs"
        >
          {{ label.name }}
        </text>
        <text
          :x="label.x"
          :y="72"
          :text-anchor="label.anchor"
          class="fill-n-slate-12 text-xl font-semibold"
        >
          {{ formatCount(label.count) }}
        </text>
        <text
          :x="label.x"
          :y="100"
          :text-anchor="label.anchor"
          class="fill-n-slate-11 text-xs"
        >
          {{ formatPct(label.pct) }}
        </text>
      </g>

      <!-- Vertical separators between stages -->
      <g>
        <line
          v-for="(pt, idx) in stagePoints"
          :key="`sep-${idx}`"
          :x1="pt.x"
          y1="10"
          :x2="pt.x"
          :y2="VIEWBOX_HEIGHT - 10"
          stroke="#e5e7eb"
          stroke-width="1"
        />
      </g>

      <!-- Funnel area path -->
      <path :d="funnelPath" fill="url(#funnelGradient)" />
    </svg>
  </div>
</template>
