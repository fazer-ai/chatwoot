<script setup>
import { ref, computed, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useKeyboardNavigableList } from 'dashboard/composables/useKeyboardNavigableList';
import SearchAPI from 'dashboard/api/search';

const props = defineProps({
  searchKey: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['selectConversation']);

const { t } = useI18n();

const listRef = ref(null);
const selectedIndex = ref(0);
const loading = ref(false);
const conversations = ref([]);

let debounceTimer = null;

const items = computed(() => {
  return conversations.value.map(conv => ({
    id: conv.id,
    type: 'conversation',
    displayName: String(conv.id),
    name: String(conv.id),
    contactName: conv.contact?.name || '',
    contactThumbnail: conv.contact?.thumbnail || '',
    inboxName: conv.inbox?.name || '',
  }));
});

async function fetchConversations(query) {
  if (!query || !query.trim()) {
    conversations.value = [];
    return;
  }
  loading.value = true;
  try {
    const { data } = await SearchAPI.conversations({ q: query.trim() });
    conversations.value = data.payload?.conversations || [];
  } catch {
    conversations.value = [];
  } finally {
    loading.value = false;
  }
}

watch(
  () => props.searchKey,
  newKey => {
    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => fetchConversations(newKey), 300);
  },
  { immediate: true }
);

watch(items, newItems => {
  if (newItems.length < selectedIndex.value + 1) {
    selectedIndex.value = 0;
  }
});

const adjustScroll = () => {
  nextTick(() => {
    if (listRef.value) {
      const el = listRef.value.querySelector(
        `#conversation-item-${selectedIndex.value}`
      );
      if (el) {
        el.scrollIntoView({ block: 'nearest', behavior: 'auto' });
      }
    }
  });
};

const onSelect = () => {
  const item = items.value[selectedIndex.value];
  if (item) emit('selectConversation', item);
};

useKeyboardNavigableList({
  items,
  onSelect,
  adjustScroll,
  selectedIndex,
});

const onHover = index => {
  selectedIndex.value = index;
};

const onItemSelect = index => {
  selectedIndex.value = index;
  onSelect();
};
</script>

<template>
  <div>
    <ul
      v-if="items.length"
      ref="listRef"
      class="vertical dropdown menu mention--box bg-n-solid-1 p-1 rounded-xl text-sm overflow-auto absolute w-[28rem] max-w-[calc(100vw-2rem)] z-20 shadow-md left-0 leading-[1.2] bottom-full max-h-[12.5rem] border border-solid border-n-strong"
      role="listbox"
    >
      <li
        class="px-2 py-1.5 text-xs font-medium tracking-wide capitalize text-n-slate-11"
      >
        {{ t('INTERNAL_CHAT.CONVERSATION_MENTION.HEADER') }}
      </li>
      <li
        v-for="(item, index) in items"
        :id="`conversation-item-${index}`"
        :key="item.id"
      >
        <div
          :class="{ 'bg-n-alpha-black2': index === selectedIndex }"
          class="flex items-center gap-2 px-2 py-1 rounded-md cursor-pointer"
          role="option"
          @click="onItemSelect(index)"
          @mouseover="onHover(index)"
        >
          <span
            class="flex-shrink-0 font-medium text-n-brand"
            :class="{ 'text-n-brand': index === selectedIndex }"
          >
            {{ t('INTERNAL_CHAT.CONVERSATION_MENTION.PREFIX') }}{{ item.id }}
          </span>
          <span
            class="flex-1 truncate text-n-slate-11"
            :class="{ 'text-n-slate-12': index === selectedIndex }"
          >
            {{ item.contactName }}
          </span>
          <span class="flex-shrink-0 text-xs text-n-slate-10 truncate max-w-24">
            {{ item.inboxName }}
          </span>
        </div>
      </li>
    </ul>
    <ul
      v-else-if="!loading"
      class="vertical dropdown menu mention--box bg-n-solid-1 p-1 rounded-xl text-sm overflow-auto absolute w-[28rem] max-w-[calc(100vw-2rem)] z-20 shadow-md left-0 leading-[1.2] bottom-full max-h-[12.5rem] border border-solid border-n-strong"
    >
      <li class="px-2 py-2 text-xs text-n-slate-10">
        {{
          searchKey?.trim()
            ? t('INTERNAL_CHAT.CONVERSATION_MENTION.NO_RESULTS')
            : t('INTERNAL_CHAT.CONVERSATION_MENTION.TYPE_TO_SEARCH')
        }}
      </li>
    </ul>
  </div>
</template>
