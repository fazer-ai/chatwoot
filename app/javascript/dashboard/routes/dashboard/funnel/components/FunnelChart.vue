<script setup>
import { computed, ref } from 'vue';

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

// Two colors split each stage's count by the conversation's current
// `ai_enabled` flag: a lime gradient for AI-handled, blue for manual.
// The reference design Auris asked us to match uses lime as the dominant
// "system" tone, blue as the highlight "human-touch" band underneath.
const AI_COLOR = '#84cc16'; // tailwind lime-500
const MANUAL_COLOR = '#3b82f6'; // tailwind blue-500

// Max stage TOTAL anchors the funnel height — the AI/manual split sits
// inside that total. Using the largest stage (vs. always the first) keeps
// the chart honest when a downstream stage received more entries than the
// top: the bar reaches full height where the data actually peaks.
const maxCount = computed(() => {
  const counts = props.stages.map(s => s.count || 0);
  return Math.max(1, ...counts);
});

const stagePoints = computed(() => {
  const n = props.stages.length;
  if (n === 0) return [];

  return props.stages.map((stage, i) => {
    const total = stage.count || 0;
    const ai = stage.countAi || 0;
    const totalRatio = total / maxCount.value;
    const halfHeight = (totalRatio * FUNNEL_HEIGHT) / 2;
    // AI sits on top of the band, manual underneath — `splitY` separates them.
    // Sliding it from `topY` to `botY` by the AI proportion of the total.
    const aiProportion = total === 0 ? 0 : ai / total;
    const topY = MIDPOINT - halfHeight;
    const botY = MIDPOINT + halfHeight;
    const splitY = topY + aiProportion * (botY - topY);
    // Spread stages evenly. With a single stage, center it.
    const x = n === 1 ? VIEWBOX_WIDTH / 2 : (i / (n - 1)) * VIEWBOX_WIDTH;
    return {
      x,
      topY,
      splitY,
      botY,
      count: total,
      stage,
    };
  });
});

// Cubic Bezier between consecutive Y values across all stage X positions.
// Used for each of the three horizontal edges of the stacked funnel (top,
// AI/manual split, bottom). Control points sit at the midpoint X to give the
// curve gentle S-shapes instead of straight slopes.
const smoothCurve = (pts, yKey) => {
  if (pts.length === 0) return '';

  let d = `M ${pts[0].x.toFixed(2)} ${pts[0][yKey].toFixed(2)}`;
  for (let i = 1; i < pts.length; i += 1) {
    const prev = pts[i - 1];
    const curr = pts[i];
    const midX = (prev.x + curr.x) / 2;
    d += ` C ${midX.toFixed(2)} ${prev[yKey].toFixed(2)}, ${midX.toFixed(2)} ${curr[yKey].toFixed(2)}, ${curr.x.toFixed(2)} ${curr[yKey].toFixed(2)}`;
  }
  return d;
};

// Reverse cubic Bezier (right-to-left), used to close a polygon by walking
// back along the lower edge after drawing the upper edge left-to-right.
const reverseCurve = (pts, yKey) => {
  let d = '';
  for (let i = pts.length - 2; i >= 0; i -= 1) {
    const next = pts[i + 1];
    const curr = pts[i];
    const midX = (next.x + curr.x) / 2;
    d += ` C ${midX.toFixed(2)} ${next[yKey].toFixed(2)}, ${midX.toFixed(2)} ${curr[yKey].toFixed(2)}, ${curr.x.toFixed(2)} ${curr[yKey].toFixed(2)}`;
  }
  return d;
};

// AI region: top edge + split edge (walked back). Manual region: split edge
// + bottom edge (walked back). Each ends with a line to the right edge so
// the polygon closes cleanly.
const aiPath = computed(() => {
  const pts = stagePoints.value;
  if (pts.length === 0) return '';

  const last = pts[pts.length - 1];
  return [
    smoothCurve(pts, 'topY'),
    `L ${last.x.toFixed(2)} ${last.splitY.toFixed(2)}`,
    reverseCurve(pts, 'splitY'),
    'Z',
  ].join(' ');
});

const manualPath = computed(() => {
  const pts = stagePoints.value;
  if (pts.length === 0) return '';

  const last = pts[pts.length - 1];
  return [
    smoothCurve(pts, 'splitY'),
    `L ${last.x.toFixed(2)} ${last.botY.toFixed(2)}`,
    reverseCurve(pts, 'botY'),
    'Z',
  ].join(' ');
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

// Hover hit zones: one invisible rect per stage, spanning the half-distance
// to its left and right neighbors so a mouse anywhere over the stage's
// vertical column triggers its tooltip. Edge stages anchor to the viewBox
// boundary on their outer side.
const hoverZones = computed(() => {
  const pts = stagePoints.value;
  if (pts.length === 0) return [];

  return pts.map((pt, i) => {
    const leftBound = i === 0 ? 0 : (pts[i - 1].x + pt.x) / 2;
    const rightBound =
      i === pts.length - 1 ? VIEWBOX_WIDTH : (pt.x + pts[i + 1].x) / 2;
    return {
      x: leftBound,
      width: rightBound - leftBound,
      stage: pt.stage,
    };
  });
});

const hoveredIdx = ref(null);

const hoveredTooltip = computed(() => {
  if (hoveredIdx.value === null) return null;
  const stage = props.stages[hoveredIdx.value];
  if (!stage) return null;

  const total = stage.count || 0;
  const ai = stage.countAi || 0;
  const manual = stage.countManual || 0;
  // Per-stage share — the split is meaningful relative to the stage's own
  // total (not relative to total leads), so each stage's two slices always
  // add up to 100%.
  const aiPct = total === 0 ? 0 : (ai / total) * 100;
  const manualPct = total === 0 ? 0 : (manual / total) * 100;
  // X positioning: percentage of the viewBox so it works regardless of the
  // SVG's rendered width. Tooltip sits over the funnel area, just above the
  // stage's split line.
  const x = stagePoints.value[hoveredIdx.value].x;
  return {
    name: stage.name,
    aiCount: ai,
    manualCount: manual,
    aiPct,
    manualPct,
    leftPct: (x / VIEWBOX_WIDTH) * 100,
  };
});
</script>

<template>
  <div class="w-full relative">
    <svg
      class="w-full h-auto"
      :viewBox="`0 0 ${VIEWBOX_WIDTH} ${VIEWBOX_HEIGHT}`"
      preserveAspectRatio="xMidYMid meet"
      role="img"
      :aria-label="$t('FUNNEL_CONVERSION_REPORTS.CHART_ARIA_LABEL')"
    >
      <defs>
        <linearGradient id="funnelGradientAi" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" :stop-color="AI_COLOR" stop-opacity="0.45" />
          <stop offset="100%" :stop-color="AI_COLOR" stop-opacity="1.0" />
        </linearGradient>
        <linearGradient id="funnelGradientManual" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" :stop-color="MANUAL_COLOR" stop-opacity="0.55" />
          <stop offset="100%" :stop-color="MANUAL_COLOR" stop-opacity="1.0" />
        </linearGradient>
      </defs>

      <!-- Labels above each stage: name, total count, pct. -->
      <g v-for="label in labelsForStages" :key="label.key">
        <text
          :x="label.x"
          :y="32"
          :text-anchor="label.anchor"
          class="fill-n-slate-11 text-lg"
        >
          {{ label.name }}
        </text>
        <text
          :x="label.x"
          :y="72"
          :text-anchor="label.anchor"
          class="fill-n-slate-12 text-3xl font-semibold"
        >
          {{ formatCount(label.count) }}
        </text>
        <text
          :x="label.x"
          :y="100"
          :text-anchor="label.anchor"
          class="fill-n-slate-11 text-lg"
        >
          {{ formatPct(label.pct) }}
        </text>
      </g>

      <!-- Vertical separators between stages — start 10px above the funnel
           top so they read clearly without clipping the label text just
           above them (pct baseline sits at y=100, font-size ~12px). -->
      <g>
        <line
          v-for="(pt, idx) in stagePoints"
          :key="`sep-${idx}`"
          :x1="pt.x"
          :y1="FUNNEL_TOP - 10"
          :x2="pt.x"
          :y2="VIEWBOX_HEIGHT - 10"
          stroke="#d1d5db"
          stroke-width="1"
        />
      </g>

      <!-- Funnel area paths. AI sits on top (lime), manual is the band
           underneath (blue). Drawing manual first so AI's bottom edge
           naturally overlays the split boundary without antialiasing seams. -->
      <path :d="manualPath" fill="url(#funnelGradientManual)" />
      <path :d="aiPath" fill="url(#funnelGradientAi)" />

      <!-- Invisible hit areas per stage — driven by `hoverZones`. Sitting
           on top of the funnel paths so hover targets the entire column,
           not just the colored band. -->
      <g>
        <rect
          v-for="(zone, idx) in hoverZones"
          :key="`hit-${idx}`"
          :x="zone.x"
          :y="FUNNEL_TOP - 10"
          :width="zone.width"
          :height="VIEWBOX_HEIGHT - FUNNEL_TOP + 10"
          fill="transparent"
          @mouseenter="hoveredIdx = idx"
          @mouseleave="hoveredIdx = null"
        />
      </g>
    </svg>

    <!-- Floating tooltip with the per-stage AI/manual split. Positioned in
         percentages of the wrapper width so it tracks the stage regardless
         of the SVG's actual rendered width. -->
    <div
      v-if="hoveredTooltip"
      class="absolute pointer-events-none z-10 top-[22%] -translate-x-1/2 -translate-y-full px-3 py-2 rounded-md shadow-md bg-n-solid-1 outline outline-1 outline-n-container text-xs whitespace-nowrap"
      :style="{ left: `${hoveredTooltip.leftPct}%` }"
    >
      <div class="font-medium text-n-slate-12 mb-1">
        {{ hoveredTooltip.name }}
      </div>
      <div class="flex items-center gap-1.5 text-n-slate-12">
        <span
          class="w-2.5 h-2.5 rounded-sm flex-shrink-0"
          :style="{ backgroundColor: AI_COLOR }"
        />
        <span>
          {{
            $t('FUNNEL_CONVERSION_REPORTS.TOOLTIP_STAT', {
              label: $t('FUNNEL_CONVERSION_REPORTS.LEGEND.AI'),
              pct: formatPct(hoveredTooltip.aiPct),
              count: formatCount(hoveredTooltip.aiCount),
            })
          }}
        </span>
      </div>
      <div class="flex items-center gap-1.5 text-n-slate-12 mt-0.5">
        <span
          class="w-2.5 h-2.5 rounded-sm flex-shrink-0"
          :style="{ backgroundColor: MANUAL_COLOR }"
        />
        <span>
          {{
            $t('FUNNEL_CONVERSION_REPORTS.TOOLTIP_STAT', {
              label: $t('FUNNEL_CONVERSION_REPORTS.LEGEND.MANUAL'),
              pct: formatPct(hoveredTooltip.manualPct),
              count: formatCount(hoveredTooltip.manualCount),
            })
          }}
        </span>
      </div>
    </div>

    <!-- Legend mapping color → semantic. Compact so it fits next to the
         loss-reasons donut on md+. -->
    <div
      class="flex items-center justify-center gap-4 mt-2 text-xs text-n-slate-11"
    >
      <div class="flex items-center gap-1.5">
        <span
          class="w-3 h-3 rounded-sm flex-shrink-0"
          :style="{ backgroundColor: AI_COLOR }"
        />
        <span>{{ $t('FUNNEL_CONVERSION_REPORTS.LEGEND.AI') }}</span>
      </div>
      <div class="flex items-center gap-1.5">
        <span
          class="w-3 h-3 rounded-sm flex-shrink-0"
          :style="{ backgroundColor: MANUAL_COLOR }"
        />
        <span>{{ $t('FUNNEL_CONVERSION_REPORTS.LEGEND.MANUAL') }}</span>
      </div>
    </div>
  </div>
</template>
