<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  stages: { type: Array, required: true },
  conversationsByStage: { type: Object, required: true },
});

const { t } = useI18n();

const collapsed = ref({});

const orderedStages = computed(() =>
  [...props.stages].sort((a, b) => {
    if (a.position !== b.position) return a.position - b.position;
    return a.id - b.id;
  })
);

const cardsFor = stage => props.conversationsByStage[stage.name] || [];

const toggle = stageName => {
  collapsed.value = {
    ...collapsed.value,
    [stageName]: !collapsed.value[stageName],
  };
};
</script>

<template>
  <div class="flex-1 min-h-0 overflow-y-auto px-6 py-4">
    <div class="flex flex-col gap-3 max-w-5xl">
      <section
        v-for="stage in orderedStages"
        :key="stage.id"
        class="rounded-lg border border-n-weak bg-n-surface-1 overflow-hidden"
      >
        <button
          type="button"
          class="flex items-center justify-between gap-3 w-full px-4 py-2.5 text-left hover:bg-n-alpha-2"
          @click="toggle(stage.name)"
        >
          <div class="flex items-center gap-2 min-w-0">
            <span
              class="i-lucide-chevron-down size-4 text-n-slate-11 transition-transform flex-shrink-0"
              :class="{ '-rotate-90': collapsed[stage.name] }"
            />
            <span
              class="inline-block size-3 rounded-full flex-shrink-0"
              :style="{ backgroundColor: stage.color || '#94a3b8' }"
            />
            <span class="text-sm font-medium text-n-slate-12 truncate">
              {{ stage.description || stage.name }}
            </span>
            <span class="text-[11px] text-n-slate-11 truncate">
              {{ t('FUNNEL.STAGE.LABEL_PREFIX', { name: stage.name }) }}
            </span>
            <span
              class="text-xs text-n-slate-11 ltr:ml-auto rtl:mr-auto flex-shrink-0"
            >
              {{ stage.count }}
            </span>
          </div>
        </button>
        <div v-if="!collapsed[stage.name]" class="border-t border-n-weak">
          <table class="w-full text-sm">
            <thead class="bg-n-alpha-1">
              <tr class="text-left text-xs text-n-slate-11">
                <th class="px-4 py-2 font-medium">
                  {{ t('FUNNEL.LIST.ID_HEADER') }}
                </th>
                <th class="px-4 py-2 font-medium">
                  {{ t('FUNNEL.LIST.CONTACT') }}
                </th>
                <th class="px-4 py-2 font-medium">
                  {{ t('FUNNEL.LIST.PHONE') }}
                </th>
                <th class="px-4 py-2 font-medium">
                  {{ t('FUNNEL.LIST.INBOX') }}
                </th>
                <th class="px-4 py-2 font-medium">{{ t('FUNNEL.LIST.AI') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="conversation in cardsFor(stage)"
                :key="conversation.id"
                class="border-t border-n-weak hover:bg-n-alpha-1"
              >
                <td class="px-4 py-2 text-n-slate-11">
                  {{ t('FUNNEL.LIST.ID_VALUE', { id: conversation.id }) }}
                </td>
                <td class="px-4 py-2 font-medium text-n-slate-12">
                  {{ conversation.contact?.name }}
                </td>
                <td class="px-4 py-2 text-n-slate-11">
                  {{ conversation.contact?.phone_number }}
                </td>
                <td class="px-4 py-2 text-n-slate-11">
                  {{ conversation.inbox?.name }}
                </td>
                <td class="px-4 py-2">
                  <span
                    :class="
                      conversation.ai_enabled !== false
                        ? 'bg-n-teal-9 text-white'
                        : 'bg-n-ruby-9 text-white'
                    "
                    class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-medium"
                  >
                    <span class="size-1.5 rounded-full bg-white" />
                    {{
                      conversation.ai_enabled !== false
                        ? t('FUNNEL.CARD.AI_ON')
                        : t('FUNNEL.CARD.AI_OFF')
                    }}
                  </span>
                </td>
              </tr>
              <tr v-if="cardsFor(stage).length === 0">
                <td
                  colspan="5"
                  class="px-4 py-6 text-center text-xs text-n-slate-11"
                >
                  {{ t('FUNNEL.LIST.EMPTY') }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
  </div>
</template>
