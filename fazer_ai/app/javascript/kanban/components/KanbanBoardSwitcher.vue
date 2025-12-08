<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  boards: {
    type: Array,
    default: () => [],
  },
  activeBoardId: {
    type: Number,
    default: null,
  },
});

const emit = defineEmits(['close', 'createBoard']);

const { t } = useI18n();
const store = useStore();

const preferences = computed(() => store.state.kanban.preferences);
const favoriteBoardIds = computed(
  () => preferences.value?.favorite_board_ids || []
);

const favoriteBoards = computed(() => {
  return props.boards.filter(f => favoriteBoardIds.value.includes(f.id));
});

const otherBoards = computed(() => {
  return props.boards.filter(f => !favoriteBoardIds.value.includes(f.id));
});

const boardGroups = computed(() => {
  const groups = [];
  const favs = favoriteBoards.value;
  const others = otherBoards.value;

  if (favs.length > 0) {
    groups.push({ title: t('KANBAN.BOARDS.FAVORITES'), items: favs });
    if (others.length > 0) {
      groups.push({ title: t('KANBAN.BOARDS.ALL_BOARDS'), items: others });
    }
  } else {
    groups.push({ title: null, items: props.boards });
  }
  return groups;
});

const toggleFavorite = async boardId => {
  await store.dispatch('kanban/toggleFavoriteBoard', boardId);
};

const isActive = boardId => boardId === props.activeBoardId;

const openCreateBoardDialog = () => {
  emit('createBoard');
  emit('close');
};
</script>

<template>
  <div
    class="pt-5 pb-3 bg-n-alpha-3 backdrop-blur-[100px] outline outline-n-container outline-1 z-50 absolute w-[24rem] rounded-xl shadow-md flex flex-col gap-4 ltr:left-0 rtl:right-0"
  >
    <div
      class="flex items-center justify-between gap-4 px-6 pb-3 border-b border-n-alpha-2"
    >
      <div class="flex flex-col gap-1">
        <div class="flex items-center gap-2">
          <h2 class="text-base font-medium text-n-slate-12 w-fit">
            {{ t('KANBAN.BOARDS.SWITCHER_TITLE') }}
          </h2>
        </div>
        <p class="text-sm text-n-slate-11">
          {{ t('KANBAN.BOARDS.SWITCHER_DESCRIPTION') }}
        </p>
      </div>
      <Button
        color="slate"
        icon="i-lucide-plus"
        size="sm"
        class="!bg-n-alpha-2 hover:!bg-n-alpha-3 whitespace-nowrap min-w-fit"
        @click="openCreateBoardDialog"
      >
        {{ t('KANBAN.BOARDS.NEW_BOARD') }}
      </Button>
    </div>
    <div
      v-if="boards.length > 0"
      class="flex flex-col gap-4 px-4 pb-2 overflow-y-auto max-h-[60vh]"
    >
      <div
        v-for="(group, groupIndex) in boardGroups"
        :key="groupIndex"
        class="flex flex-col gap-2"
      >
        <h3
          v-if="group.title"
          class="text-xs font-medium text-n-slate-10 px-2 uppercase tracking-wider"
        >
          {{ group.title }}
        </h3>
        <div class="flex flex-col gap-1">
          <router-link
            v-for="board in group.items"
            :key="board.id"
            :to="{ name: 'kanban_board_show', params: { boardId: board.id } }"
            class="group flex items-center justify-between p-2 rounded-lg hover:bg-n-alpha-2 cursor-pointer transition-colors h-9"
            @click="emit('close')"
          >
            <div class="flex items-center gap-2 min-w-0 flex-1">
              <Button
                :icon="
                  favoriteBoardIds.includes(board.id)
                    ? 'i-ri-star-fill text-yellow-500'
                    : 'i-lucide-star'
                "
                variant="ghost"
                color="slate"
                size="xs"
                class="!p-0 h-5 w-5 flex-shrink-0"
                :class="{
                  'opacity-100': favoriteBoardIds.includes(board.id),
                }"
                @click.prevent.stop="toggleFavorite(board.id)"
              />
              <span class="text-sm font-medium truncate text-n-slate-12">
                {{ board.name }}
              </span>
            </div>
            <div
              v-if="isActive(board.id)"
              class="i-lucide-check text-n-teal-10 w-4 h-4 flex-shrink-0 ml-2"
            />
          </router-link>
        </div>
      </div>
    </div>
    <div v-else class="px-6 pb-2">
      <p class="text-xs text-n-slate-9">
        {{ t('KANBAN.BOARDS.EMPTY_SWITCHER') }}
      </p>
    </div>
  </div>
</template>
