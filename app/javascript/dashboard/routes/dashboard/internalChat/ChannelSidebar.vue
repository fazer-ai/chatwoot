<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import CreateChannelModal from './CreateChannelModal.vue';
import CreateDMModal from './CreateDMModal.vue';
import CreateCategoryModal from './CreateCategoryModal.vue';
import Draggable from 'vuedraggable';

const store = useStore();
const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const currentRole = useMapGetter('getCurrentRole');
const isAdmin = computed(() => currentRole.value === 'administrator');

const searchQuery = ref('');
const createChannelModalRef = ref(null);
const createDMModalRef = ref(null);
const createCategoryModalRef = ref(null);

const collapsedSections = ref(
  new Set(
    JSON.parse(localStorage.getItem('internal_chat_collapsed_sections') || '[]')
  )
);

function toggleSection(key) {
  if (collapsedSections.value.has(key)) {
    collapsedSections.value.delete(key);
  } else {
    collapsedSections.value.add(key);
  }
  // Trigger reactivity
  collapsedSections.value = new Set(collapsedSections.value);
  localStorage.setItem(
    'internal_chat_collapsed_sections',
    JSON.stringify([...collapsedSections.value])
  );
}

function isSectionCollapsed(key) {
  return collapsedSections.value.has(key);
}

const channels = computed(() => {
  return store.getters['internalChat/getChannels'] || [];
});

const categories = computed(() => {
  return store.getters['internalChat/getCategories'] || [];
});

const favoriteChannels = computed(() => {
  return store.getters['internalChat/getFavoriteChannels'] || [];
});

const dmChannels = computed(() => {
  return store.getters['internalChat/getDMChannels'] || [];
});

const activeChannelId = computed(() => {
  return Number(route.params.channelId) || null;
});

const accountId = computed(() => {
  return route.params.accountId;
});

function getDMDisplayName(channel) {
  if (channel.channel_type !== 'dm') return channel.name || '';
  const currentUserId = store.getters.getCurrentUser?.id;
  const otherMember = (channel.members || []).find(
    m => m.user_id !== currentUserId
  );
  return otherMember?.name || channel.name || 'Direct Message';
}

function getDisplayName(channel) {
  if (channel.channel_type === 'dm') return getDMDisplayName(channel);
  return channel.name || '';
}

function matchesSearch(ch, query) {
  const name = getDisplayName(ch).toLowerCase();
  if (name.includes(query)) return true;
  if (ch.channel_type !== 'dm' && ch.description) {
    return ch.description.toLowerCase().includes(query);
  }
  return false;
}

const filteredChannelsByCategory = computed(() => {
  return categoryId => {
    let categoryChannels =
      store.getters['internalChat/getChannelsByCategory'](categoryId) || [];
    if (searchQuery.value) {
      const query = searchQuery.value.toLowerCase();
      categoryChannels = categoryChannels.filter(ch =>
        matchesSearch(ch, query)
      );
    }
    return [...categoryChannels].sort((a, b) => {
      if (a.muted && !b.muted) return 1;
      if (!a.muted && b.muted) return -1;
      return 0;
    });
  };
});

const filteredDMChannels = computed(() => {
  const dms = dmChannels.value || [];
  if (!searchQuery.value) return dms;
  const query = searchQuery.value.toLowerCase();
  return dms.filter(ch => matchesSearch(ch, query));
});

const filteredFavoriteChannels = computed(() => {
  const favs = favoriteChannels.value || [];
  if (!searchQuery.value) return favs;
  const query = searchQuery.value.toLowerCase();
  return favs.filter(ch => matchesSearch(ch, query));
});

const uncategorizedChannels = computed(() => {
  let uncategorized = channels.value.filter(
    ch => ch.channel_type !== 'dm' && !ch.category_id
  );
  if (searchQuery.value) {
    const query = searchQuery.value.toLowerCase();
    uncategorized = uncategorized.filter(ch => matchesSearch(ch, query));
  }
  return [...uncategorized].sort((a, b) => {
    if (a.muted && !b.muted) return 1;
    if (!a.muted && b.muted) return -1;
    return 0;
  });
});

const isDraftsRoute = computed(() => {
  return route.name === 'internal_chat_drafts';
});

const localUncategorizedChannels = ref([]);
const localCategoryChannels = ref({});

watch(
  uncategorizedChannels,
  val => {
    localUncategorizedChannels.value = [...val];
  },
  { immediate: true }
);

watch(
  [categories, () => filteredChannelsByCategory.value],
  () => {
    const map = {};
    categories.value.forEach(cat => {
      map[cat.id] = [...filteredChannelsByCategory.value(cat.id)];
    });
    localCategoryChannels.value = map;
  },
  { immediate: true }
);

function getCategoryChannelList(categoryId) {
  return localCategoryChannels.value[categoryId] || [];
}

function setCategoryChannelList(categoryId, list) {
  localCategoryChannels.value = {
    ...localCategoryChannels.value,
    [categoryId]: list,
  };
}

function onDragEnd(event) {
  const channelId = Number(event.item.dataset.channelId);
  const toCategoryId = event.to.dataset.categoryId || null;
  store.dispatch('internalChat/update', {
    channelId,
    channel: { category_id: toCategoryId ? Number(toCategoryId) : null },
  });
}

function navigateToChannel(channel) {
  const routeName =
    channel.channel_type === 'dm'
      ? 'internal_chat_dm'
      : 'internal_chat_channel';
  router.push({
    name: routeName,
    params: { accountId: accountId.value, channelId: channel.id },
  });
}

function navigateToDrafts() {
  router.push({
    name: 'internal_chat_drafts',
    params: { accountId: accountId.value },
  });
}

function getChannelIcon(channel) {
  if (channel.channel_type === 'dm') return 'i-lucide-message-circle';
  if (channel.channel_type === 'private_channel') return 'i-lucide-lock';
  return 'i-lucide-hash';
}

function openCreateChannel() {
  createChannelModalRef.value?.open();
}

function openCreateDM() {
  createDMModalRef.value?.open();
}

function openCreateCategory() {
  createCategoryModalRef.value?.open();
}
</script>

<template>
  <div class="flex h-full w-64 flex-col border-r border-n-slate-5 bg-n-solid-2">
    <div class="px-3 pt-3 pb-1">
      <h1 class="mb-2 text-base font-semibold text-n-slate-12">
        {{ t('INTERNAL_CHAT.TITLE') }}
      </h1>
      <div class="relative">
        <Icon
          icon="i-lucide-search"
          class="absolute left-2.5 top-1/2 size-3.5 -translate-y-1/2 text-n-slate-10"
        />
        <input
          v-model="searchQuery"
          type="text"
          :placeholder="t('INTERNAL_CHAT.SEARCH_PLACEHOLDER')"
          :aria-label="t('INTERNAL_CHAT.SEARCH_PLACEHOLDER')"
          class="w-full rounded-lg border border-n-slate-6 bg-n-solid-1 py-1.5 pl-9 pr-3 text-sm text-n-slate-12 placeholder-n-slate-10 outline-none focus:border-n-brand"
        />
      </div>
    </div>
    <div class="px-1.5 pb-1">
      <button
        class="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-sm transition-colors"
        :class="
          isDraftsRoute
            ? 'bg-n-alpha-2 text-n-slate-12'
            : 'text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12'
        "
        @click="navigateToDrafts"
      >
        <Icon icon="i-lucide-file-edit" class="size-4 flex-shrink-0" />
        <span class="flex-1 text-left">{{
          t('INTERNAL_CHAT.DRAFT.TITLE')
        }}</span>
      </button>
    </div>
    <div class="flex-1 overflow-y-auto px-1.5">
      <!-- Favorites -->
      <div v-if="filteredFavoriteChannels.length > 0" class="mb-3">
        <h3
          class="flex cursor-pointer items-center gap-1.5 px-2 py-1 text-xs font-semibold uppercase tracking-wider text-n-slate-10"
          @click="toggleSection('favorites')"
        >
          <Icon
            :icon="
              isSectionCollapsed('favorites')
                ? 'i-lucide-chevron-right'
                : 'i-lucide-chevron-down'
            "
            class="size-3"
          />
          <Icon icon="i-lucide-star" class="size-3" />
          {{ t('INTERNAL_CHAT.FAVORITES') }}
        </h3>
        <div v-show="!isSectionCollapsed('favorites')">
          <button
            v-for="channel in filteredFavoriteChannels"
            :key="`fav-${channel.id}`"
            class="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-sm transition-colors"
            :class="
              activeChannelId === channel.id
                ? 'bg-n-alpha-2 text-n-slate-12'
                : 'text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12'
            "
            @click="navigateToChannel(channel)"
          >
            <Icon
              :icon="getChannelIcon(channel)"
              class="size-4 flex-shrink-0"
            />
            <span class="flex-1 truncate text-left">{{
              getDisplayName(channel)
            }}</span>
            <span
              v-if="channel.unread_count > 0"
              class="flex-shrink-0 rounded-full bg-n-brand px-1.5 py-0.5 text-xs font-medium text-white"
            >
              {{ channel.unread_count }}
            </span>
          </button>
        </div>
      </div>

      <!-- Categories -->
      <div v-for="category in categories" :key="category.id" class="mb-3">
        <h3
          class="flex cursor-pointer items-center gap-1.5 px-2 py-1 text-xs font-semibold uppercase tracking-wider text-n-slate-10"
          @click="toggleSection(`category-${category.id}`)"
        >
          <Icon
            :icon="
              isSectionCollapsed(`category-${category.id}`)
                ? 'i-lucide-chevron-right'
                : 'i-lucide-chevron-down'
            "
            class="size-3"
          />
          {{ category.name }}
        </h3>
        <div v-show="!isSectionCollapsed(`category-${category.id}`)">
          <Draggable
            :list="getCategoryChannelList(category.id)"
            :disabled="!isAdmin"
            group="channels"
            item-key="id"
            ghost-class="opacity-30"
            :data-category-id="category.id"
            @update:list="list => setCategoryChannelList(category.id, list)"
            @end="onDragEnd"
          >
            <template #item="{ element: channel }">
              <button
                :data-channel-id="channel.id"
                class="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-sm transition-colors"
                :class="[
                  activeChannelId === channel.id
                    ? 'bg-n-alpha-2 text-n-slate-12'
                    : 'text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12',
                  { 'opacity-50': channel.muted },
                ]"
                @click="navigateToChannel(channel)"
              >
                <Icon
                  :icon="getChannelIcon(channel)"
                  class="size-4 flex-shrink-0"
                />
                <span class="flex-1 truncate text-left">{{
                  channel.name
                }}</span>
                <Icon
                  v-if="channel.muted"
                  icon="i-lucide-bell-off"
                  class="size-3 flex-shrink-0 text-n-slate-9"
                />
                <span
                  v-if="channel.unread_count > 0 && !channel.muted"
                  class="flex-shrink-0 rounded-full bg-n-brand px-1.5 py-0.5 text-xs font-medium text-white"
                >
                  {{ channel.unread_count }}
                </span>
              </button>
            </template>
          </Draggable>
        </div>
      </div>

      <div v-if="isAdmin" class="mb-3 px-2">
        <button
          class="flex items-center gap-1 text-xs text-n-slate-10 transition-colors hover:text-n-slate-12"
          @click="openCreateCategory"
        >
          <Icon icon="i-lucide-plus" class="size-3" />
          {{ t('INTERNAL_CHAT.CATEGORY.CREATE') }}
        </button>
      </div>

      <!-- Uncategorized channels -->
      <div class="mb-3">
        <h3
          class="flex cursor-pointer items-center justify-between px-2 py-1 text-xs font-semibold uppercase tracking-wider text-n-slate-10"
          @click="toggleSection('channels')"
        >
          <span class="flex items-center gap-1.5">
            <Icon
              :icon="
                isSectionCollapsed('channels')
                  ? 'i-lucide-chevron-right'
                  : 'i-lucide-chevron-down'
              "
              class="size-3"
            />
            {{ t('INTERNAL_CHAT.CHANNELS') }}
          </span>
          <button
            v-if="isAdmin"
            class="text-n-slate-10 transition-colors hover:text-n-slate-12"
            @click.stop="openCreateChannel"
          >
            <Icon icon="i-lucide-plus" class="size-3.5" />
          </button>
        </h3>
        <div v-show="!isSectionCollapsed('channels')">
          <Draggable
            :list="localUncategorizedChannels"
            :disabled="!isAdmin"
            group="channels"
            item-key="id"
            ghost-class="opacity-30"
            data-category-id=""
            @update:list="
              list => {
                localUncategorizedChannels = list;
              }
            "
            @end="onDragEnd"
          >
            <template #item="{ element: channel }">
              <button
                :data-channel-id="channel.id"
                class="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-sm transition-colors"
                :class="[
                  activeChannelId === channel.id
                    ? 'bg-n-alpha-2 text-n-slate-12'
                    : 'text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12',
                  { 'opacity-50': channel.muted },
                ]"
                @click="navigateToChannel(channel)"
              >
                <Icon
                  :icon="getChannelIcon(channel)"
                  class="size-4 flex-shrink-0"
                />
                <Icon
                  v-if="channel.muted"
                  icon="i-lucide-bell-off"
                  class="size-3 flex-shrink-0 text-n-slate-9"
                />
                <span class="flex-1 truncate text-left">{{
                  channel.name
                }}</span>
                <span
                  v-if="channel.unread_count > 0 && !channel.muted"
                  class="flex-shrink-0 rounded-full bg-n-brand px-1.5 py-0.5 text-xs font-medium text-white"
                >
                  {{ channel.unread_count }}
                </span>
              </button>
            </template>
          </Draggable>
        </div>
      </div>

      <!-- Direct Messages -->
      <div class="mb-3">
        <h3
          class="flex cursor-pointer items-center justify-between px-2 py-1 text-xs font-semibold uppercase tracking-wider text-n-slate-10"
          @click="toggleSection('dm')"
        >
          <span class="flex items-center gap-1.5">
            <Icon
              :icon="
                isSectionCollapsed('dm')
                  ? 'i-lucide-chevron-right'
                  : 'i-lucide-chevron-down'
              "
              class="size-3"
            />
            <Icon icon="i-lucide-message-circle" class="size-3" />
            {{ t('INTERNAL_CHAT.DIRECT_MESSAGES') }}
          </span>
          <button
            v-if="isAdmin"
            class="text-n-slate-10 transition-colors hover:text-n-slate-12"
            @click.stop="openCreateDM"
          >
            <Icon icon="i-lucide-plus" class="size-3.5" />
          </button>
        </h3>
        <div v-show="!isSectionCollapsed('dm')">
          <button
            v-for="channel in filteredDMChannels"
            :key="`dm-${channel.id}`"
            class="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-sm transition-colors"
            :class="
              activeChannelId === channel.id
                ? 'bg-n-alpha-2 text-n-slate-12'
                : 'text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12'
            "
            @click="navigateToChannel(channel)"
          >
            <Icon icon="i-lucide-message-circle" class="size-4 flex-shrink-0" />
            <span class="flex-1 truncate text-left">{{
              getDMDisplayName(channel)
            }}</span>
            <span
              v-if="channel.unread_count > 0"
              class="flex-shrink-0 rounded-full bg-n-brand px-1.5 py-0.5 text-xs font-medium text-white"
            >
              {{ channel.unread_count }}
            </span>
          </button>
        </div>
      </div>

      <!-- Empty state -->
      <div
        v-if="channels.length === 0"
        class="flex items-center justify-center py-8"
      >
        <p class="text-sm text-n-slate-10">
          {{ t('INTERNAL_CHAT.NO_CHANNELS') }}
        </p>
      </div>
    </div>

    <CreateChannelModal ref="createChannelModalRef" />
    <CreateDMModal ref="createDMModalRef" />
    <CreateCategoryModal ref="createCategoryModalRef" />
  </div>
</template>
