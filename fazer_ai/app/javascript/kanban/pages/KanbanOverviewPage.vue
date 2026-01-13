<script setup>
import { computed, onMounted, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import ThumbnailGroup from 'dashboard/components/widgets/ThumbnailGroup.vue';
import KanbanBoardModal from 'kanban/components/KanbanBoardModal.vue';
import KanbanSortMenu from 'kanban/components/KanbanSortMenu.vue';
import BasePaywallModal from 'dashboard/routes/dashboard/settings/components/BasePaywallModal.vue';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import kanbanModule from 'kanban/store/modules/kanban';
import { useBoardModal } from 'kanban/composables/useBoardModal';

const store = useStore();
const router = useRouter();
const { t } = useI18n();
const { isAdmin } = useAdmin();
const { isCloudFeatureEnabled, accountId, isOnChatwootCloud } = useAccount();
const currentUser = useMapGetter('getCurrentUser');

const fazerAiSubscription = computed(
  () => store.getters['globalConfig/getFazerAiSubscription']
);
const isFazerAiSubscriptionActive = computed(() => {
  const status = fazerAiSubscription.value?.status;
  return ['active', 'past_due', 'trialing'].includes(status);
});

const isKanbanEnabled = computed(
  () =>
    isCloudFeatureEnabled(FEATURE_FLAGS.KANBAN) &&
    isFazerAiSubscriptionActive.value
);
const isSuperAdmin = computed(() => currentUser.value?.type === 'SuperAdmin');
const paywallI18nKey = computed(() =>
  isOnChatwootCloud.value ? 'PAYWALL' : 'ENTERPRISE_PAYWALL'
);

const openBilling = () => {
  router.push({
    name: 'billing_settings_index',
    params: { accountId: accountId.value },
  });
};

if (!store.hasModule('kanban')) {
  store.registerModule('kanban', kanbanModule);
}

const boards = computed(() => store.state.kanban.boards);
const isLoading = computed(() => store.state.kanban.isLoading);
const allInboxes = computed(() => store.getters['inboxes/getInboxes']);
const preferences = computed(() => store.state.kanban.preferences);

const favoriteBoardIds = computed(
  () => preferences.value?.favorite_board_ids || []
);

const favoriteBoards = computed(() => {
  return boards.value.filter(f => favoriteBoardIds.value.includes(f.id));
});

const otherBoards = computed(() => {
  return boards.value.filter(f => !favoriteBoardIds.value.includes(f.id));
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
    groups.push({ title: null, items: boards.value });
  }
  return groups;
});

const activeSort = ref('updated_at');
const activeOrdering = ref('desc');

const fetchBoards = async (params = {}) => {
  await store.dispatch('kanban/fetchBoards', params);

  if (preferences.value?.board_sorting) {
    activeSort.value = preferences.value.board_sorting.sort;
    activeOrdering.value = preferences.value.board_sorting.order;
  }
};

const onSortChange = ({ sort, order }) => {
  activeSort.value = sort;
  activeOrdering.value = order;
  fetchBoards({ sort, order });
};

const toggleFavorite = async boardId => {
  await store.dispatch('kanban/toggleFavoriteBoard', boardId);
};

const {
  showBoardModal,
  isSavingBoard,
  openBoardModal,
  closeBoardModal,
  saveBoard,
} = useBoardModal({
  onSuccess: newBoard => {
    if (newBoard?.id) {
      router.push({
        name: 'kanban_board_show',
        params: { boardId: newBoard.id },
      });
    }
  },
  onError: error => {
    useAlert(
      parseAPIErrorResponse(error) || t('KANBAN.BOARD_MODAL.CREATE_ERROR')
    );
  },
});

onMounted(() => {
  fetchBoards();
  store.dispatch('inboxes/get');
});

const openBoardSettings = boardId => {
  router.push({ name: 'kanban_board_settings', params: { boardId } });
};

const getVisibleAgents = assignedAgents => {
  if (!assignedAgents) return [];
  // Show all agents if 4 or fewer (since +1 would take same space as one avatar)
  if (assignedAgents.length <= 4) return assignedAgents;
  // Show first 3 when 5+, leaving room for +X badge
  return assignedAgents.slice(0, 3);
};

const getRemainingAgentsCount = assignedAgents => {
  const total = assignedAgents?.length || 0;
  // Only show +X when there are 5+ agents (so X is at least 2)
  if (total <= 4) return '';
  const remaining = total - 3;
  return `+${remaining}`;
};

const getVisibleInboxes = assignedInboxes => {
  if (!assignedInboxes) return [];
  // Show all inboxes if 4 or fewer
  if (assignedInboxes.length <= 4) return assignedInboxes;
  // Show first 3 when 5+, leaving room for +X badge
  return assignedInboxes.slice(0, 3);
};

const getRemainingInboxesCount = assignedInboxes => {
  const total = assignedInboxes?.length || 0;
  // Only show +X when there are 5+ inboxes (so X is at least 2)
  if (total <= 4) return '';
  const remaining = total - 3;
  return `+${remaining}`;
};

const getAssignedInboxes = inboxIds => {
  if (!inboxIds?.length) return [];
  return allInboxes.value.filter(inbox => inboxIds.includes(inbox.id));
};
</script>

<template>
  <div
    class="flex h-full w-full flex-col overflow-hidden bg-n-background font-inter"
  >
    <!-- Feature Disabled State -->
    <template v-if="!isKanbanEnabled">
      <div
        class="flex items-center justify-center h-full min-h-[400px] px-6 py-12"
      >
        <BasePaywallModal
          feature-prefix="KANBAN"
          :i18n-key="paywallI18nKey"
          :is-super-admin="isSuperAdmin"
          :is-on-chatwoot-cloud="isOnChatwootCloud"
          @upgrade="openBilling"
        />
      </div>
    </template>

    <!-- Normal Content (when feature is enabled) -->
    <template v-else>
      <div
        class="w-full flex justify-center px-6 sm:py-8 lg:px-16 pt-6 sm:pt-8 pb-4"
      >
        <div class="w-full max-w-7xl">
          <SettingsLayout :is-loading="false">
            <template #header>
              <div class="flex items-center justify-between w-full">
                <h1 class="text-xl font-medium tracking-tight text-n-slate-12">
                  {{ t('KANBAN.OVERVIEW.TITLE') }}
                </h1>
                <div class="flex items-center gap-2">
                  <KanbanSortMenu
                    :active-sort="activeSort"
                    :active-ordering="activeOrdering"
                    @update:sort="onSortChange"
                  />
                  <Button
                    v-if="isAdmin"
                    icon="i-lucide-plus"
                    size="sm"
                    class="whitespace-nowrap"
                    @click="openBoardModal"
                  >
                    <span class="hidden md:inline">{{
                      t('KANBAN.OVERVIEW.ADD_BOARD')
                    }}</span>
                  </Button>
                </div>
              </div>
            </template>
          </SettingsLayout>
        </div>
      </div>
      <div
        class="flex-1 overflow-y-auto px-6 lg:px-16 scrollbar-custom flex justify-center"
      >
        <div class="w-full max-w-7xl">
          <template v-if="isLoading">
            <div class="flex flex-col gap-8 pb-6 animate-pulse">
              <!-- Favorites Section -->
              <div class="flex flex-col gap-4">
                <div class="h-7 bg-n-slate-4 rounded w-32" />
                <div class="flex flex-col gap-4">
                  <div
                    v-for="i in 2"
                    :key="`fav-${i}`"
                    class="flex flex-col gap-4 p-5 border rounded-xl border-n-slate-3 bg-n-alpha-1"
                  >
                    <div class="flex items-center justify-between gap-3">
                      <div class="flex items-center gap-3 w-1/2">
                        <div class="h-5 bg-n-slate-4 rounded w-48" />
                        <div class="h-5 w-8 bg-n-slate-4 rounded-full" />
                      </div>

                      <div class="flex items-center gap-2">
                        <div class="flex -space-x-1">
                          <div
                            class="h-6 w-6 rounded-full bg-n-slate-4 ring-2 ring-n-alpha-1"
                          />
                          <div
                            class="h-6 w-6 rounded-full bg-n-slate-4 ring-2 ring-n-alpha-1"
                          />
                          <div
                            class="h-6 w-6 rounded-full bg-n-slate-4 ring-2 ring-n-alpha-1"
                          />
                        </div>
                        <div class="flex -space-x-1">
                          <div
                            class="h-6 w-6 rounded-full bg-n-slate-4 ring-2 ring-n-alpha-1"
                          />
                          <div
                            class="h-6 w-6 rounded-full bg-n-slate-4 ring-2 ring-n-alpha-1"
                          />
                        </div>
                      </div>
                    </div>

                    <div class="flex gap-2">
                      <div class="h-6 w-24 bg-n-slate-4 rounded-md" />
                      <div class="h-6 w-32 bg-n-slate-4 rounded-md" />
                      <div class="h-6 w-20 bg-n-slate-4 rounded-md" />
                      <div class="h-6 w-28 bg-n-slate-4 rounded-md" />
                    </div>
                  </div>
                </div>
              </div>

              <!-- All Boards Section -->
              <div class="flex flex-col gap-4">
                <div class="h-7 bg-n-slate-4 rounded w-36" />
                <div class="flex flex-col gap-4">
                  <div
                    v-for="i in 3"
                    :key="`all-${i}`"
                    class="flex flex-col gap-4 p-5 border rounded-xl border-n-slate-3 bg-n-alpha-1"
                  >
                    <div class="flex items-center justify-between gap-3">
                      <div class="flex items-center gap-3 w-1/2">
                        <div class="h-5 bg-n-slate-4 rounded w-48" />
                        <div class="h-5 w-8 bg-n-slate-4 rounded-full" />
                      </div>

                      <div class="flex items-center gap-2">
                        <div class="flex -space-x-1">
                          <div
                            class="h-6 w-6 rounded-full bg-n-slate-4 ring-2 ring-n-alpha-1"
                          />
                          <div
                            class="h-6 w-6 rounded-full bg-n-slate-4 ring-2 ring-n-alpha-1"
                          />
                          <div
                            class="h-6 w-6 rounded-full bg-n-slate-4 ring-2 ring-n-alpha-1"
                          />
                        </div>
                        <div class="flex -space-x-1">
                          <div
                            class="h-6 w-6 rounded-full bg-n-slate-4 ring-2 ring-n-alpha-1"
                          />
                          <div
                            class="h-6 w-6 rounded-full bg-n-slate-4 ring-2 ring-n-alpha-1"
                          />
                        </div>
                      </div>
                    </div>

                    <div class="flex gap-2">
                      <div class="h-6 w-24 bg-n-slate-4 rounded-md" />
                      <div class="h-6 w-32 bg-n-slate-4 rounded-md" />
                      <div class="h-6 w-20 bg-n-slate-4 rounded-md" />
                      <div class="h-6 w-28 bg-n-slate-4 rounded-md" />
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </template>
          <template v-else-if="!boards.length">
            <div
              class="flex items-center justify-center h-full min-h-[300px] -mt-12"
            >
              <div
                class="flex flex-col items-center gap-4 max-w-md text-center"
              >
                <div
                  class="flex h-16 w-16 items-center justify-center rounded-2xl bg-n-slate-3"
                >
                  <i class="i-lucide-kanban w-8 h-8 text-n-slate-11" />
                </div>
                <div class="flex flex-col gap-2">
                  <h3 class="text-lg font-medium text-n-slate-12">
                    {{ t('KANBAN.OVERVIEW.EMPTY_TITLE') }}
                  </h3>
                  <p class="text-sm text-n-slate-11">
                    {{ t('KANBAN.OVERVIEW.EMPTY_DESCRIPTION') }}
                  </p>
                </div>
                <Button
                  v-if="isAdmin"
                  icon="i-lucide-plus"
                  size="sm"
                  @click="openBoardModal"
                >
                  {{ t('KANBAN.OVERVIEW.EMPTY_ACTION') }}
                </Button>
              </div>
            </div>
          </template>
          <template v-else-if="boards.length">
            <div class="flex flex-col gap-8 pb-6">
              <div
                v-for="(group, groupIndex) in boardGroups"
                :key="groupIndex"
                class="flex flex-col gap-4"
              >
                <h3
                  v-if="group.title"
                  class="text-lg font-medium text-n-slate-12"
                >
                  {{ group.title }}
                </h3>
                <div class="flex flex-col gap-4">
                  <router-link
                    v-for="board in group.items"
                    :key="board.id"
                    :to="{
                      name: 'kanban_board_show',
                      params: { boardId: board.id },
                    }"
                    class="group flex flex-col gap-4 p-5 border rounded-xl border-n-slate-3 bg-n-alpha-1 hover:bg-n-alpha-2 hover:border-n-slate-4 transition-all cursor-pointer"
                  >
                    <div class="flex items-center justify-between gap-3">
                      <div class="flex items-center gap-3 min-w-0">
                        <h2
                          class="text-base font-medium text-n-slate-12 truncate"
                        >
                          {{ board.name }}
                        </h2>
                        <span
                          v-if="board.total_tasks_count !== undefined"
                          class="flex h-5 min-w-[1.25rem] items-center justify-center rounded-full bg-n-slate-4 px-2 text-xs font-medium text-n-slate-12 flex-shrink-0"
                        >
                          {{ board.total_tasks_count }}
                        </span>
                        <Button
                          :icon="
                            favoriteBoardIds.includes(board.id)
                              ? 'i-ri-star-fill text-yellow-500'
                              : 'i-lucide-star'
                          "
                          variant="ghost"
                          color="slate"
                          size="xs"
                          class="opacity-0 group-hover:opacity-100 transition-opacity flex-shrink-0"
                          :class="{
                            'opacity-100': favoriteBoardIds.includes(board.id),
                          }"
                          @click.prevent.stop="toggleFavorite(board.id)"
                        />
                      </div>
                      <div class="flex items-center gap-2">
                        <ThumbnailGroup
                          v-if="
                            board.assigned_agents &&
                            board.assigned_agents.length
                          "
                          :users-list="
                            getVisibleAgents(
                              board.assigned_agents.map(agent => ({
                                ...agent,
                                thumbnail: agent.avatar_url,
                              }))
                            )
                          "
                          :size="24"
                          :show-more-thumbnails-count="
                            board.assigned_agents.length > 4
                          "
                          :more-thumbnails-text="
                            getRemainingAgentsCount(board.assigned_agents)
                          "
                        />
                        <div
                          v-if="
                            board.assigned_inbox_ids &&
                            board.assigned_inbox_ids.length
                          "
                          class="flex"
                        >
                          <div
                            v-for="inbox in getVisibleInboxes(
                              getAssignedInboxes(board.assigned_inbox_ids)
                            )"
                            :key="inbox.id"
                            v-tooltip="inbox.name"
                            class="relative flex h-6 w-6 items-center justify-center rounded-full bg-n-slate-4 text-n-slate-11 outline outline-1 outline-n-background shadow ltr:[&:not(:first-child)]:-ml-2 rtl:[&:not(:first-child)]:-mr-2"
                          >
                            <ChannelIcon class="size-3" :inbox="inbox" />
                          </div>
                          <span
                            v-if="
                              getAssignedInboxes(board.assigned_inbox_ids)
                                .length > 4
                            "
                            class="text-n-slate-11 bg-n-slate-4 outline outline-1 outline-n-background text-xs font-medium rounded-full px-2 inline-flex items-center shadow relative ltr:-ml-2 rtl:-mr-2"
                          >
                            {{
                              getRemainingInboxesCount(
                                getAssignedInboxes(board.assigned_inbox_ids)
                              )
                            }}
                          </span>
                        </div>
                        <Button
                          v-if="isAdmin"
                          icon="i-lucide-settings"
                          variant="ghost"
                          color="slate"
                          size="xs"
                          class="opacity-0 group-hover:opacity-100 transition-opacity"
                          @click.prevent.stop="openBoardSettings(board.id)"
                        />
                      </div>
                    </div>

                    <div
                      v-if="board.steps_summary && board.steps_summary.length"
                      class="flex flex-wrap gap-2"
                    >
                      <div
                        v-for="step in board.steps_summary"
                        :key="step.id"
                        class="flex items-center gap-2 px-2 py-1 rounded-md bg-n-background border border-n-slate-3"
                      >
                        <div
                          class="w-2 h-2 rounded-full"
                          :style="{ backgroundColor: step.color }"
                        />
                        <span
                          class="text-xs text-n-slate-11 truncate max-w-[200px]"
                          >{{ step.name }}
                        </span>
                        <span
                          class="flex h-4 min-w-[1rem] items-center justify-center rounded-full bg-n-slate-4 px-1.5 text-xs font-medium text-n-slate-12"
                        >
                          {{ step.tasks_count }}
                        </span>
                      </div>
                    </div>
                  </router-link>
                </div>
              </div>
            </div>
          </template>
        </div>
        <KanbanBoardModal
          :show="showBoardModal"
          :is-saving="isSavingBoard"
          @close="closeBoardModal"
          @save="saveBoard"
        />
      </div>
    </template>
  </div>
</template>

<style scoped>
:deep(main) {
  @apply flex-1 flex flex-col min-h-0;
}
</style>
