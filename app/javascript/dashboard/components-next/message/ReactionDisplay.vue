<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';

const props = defineProps({
  reactions: {
    type: Array,
    default: () => [],
  },
  currentUserId: {
    type: Number,
    default: null,
  },
  pendingEmojis: {
    type: Set,
    default: () => new Set(),
  },
  alignment: {
    type: String,
    default: 'left',
    validator: value => ['left', 'right'].includes(value),
  },
  readOnly: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['toggle']);

const { t } = useI18n();

const showPopover = ref(false);

const groupedReactions = computed(() => {
  const groups = {};
  props.reactions.forEach(reaction => {
    const { emoji } = reaction;
    if (!groups[emoji]) {
      groups[emoji] = { emoji, count: 0, isMine: false, users: [] };
    }
    groups[emoji].count += 1;
    const isMine =
      (reaction.senderType === 'user' &&
        reaction.senderId === props.currentUserId) ||
      (reaction.messageType === 1 && reaction.senderId == null);
    if (isMine) groups[emoji].isMine = true;
    groups[emoji].users.push({
      id: reaction.id,
      name: reaction.sender?.name || '',
      isMine,
    });
  });
  return Object.values(groups);
});

const uniqueEmojis = computed(() => groupedReactions.value.map(g => g.emoji));

const totalCount = computed(() =>
  groupedReactions.value.reduce((sum, g) => sum + g.count, 0)
);

const isMine = computed(() => groupedReactions.value.some(g => g.isMine));

const isAnyPending = computed(() =>
  uniqueEmojis.value.some(emoji => props.pendingEmojis.has(emoji))
);

function togglePopover() {
  showPopover.value = !showPopover.value;
}

function closePopover() {
  showPopover.value = false;
}

function handleRowClick(emoji, user) {
  if (!user.isMine) return;
  if (props.readOnly) return;
  emit('toggle', emoji);
  closePopover();
}
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div
    v-if="groupedReactions.length"
    class="relative -mt-1 flex flex-wrap items-center gap-1"
  >
    <button
      type="button"
      class="inline-flex items-center gap-1 rounded-full border px-1.5 py-0.5 text-xs transition-colors disabled:opacity-60 disabled:cursor-not-allowed"
      :class="
        isMine
          ? 'border-n-brand bg-n-alpha-2 text-n-brand'
          : 'border-n-slate-6 bg-n-alpha-1 text-n-slate-12 hover:bg-n-alpha-2'
      "
      :disabled="isAnyPending"
      @click="togglePopover"
    >
      <span class="inline-flex items-center gap-0.5">
        <span v-for="emoji in uniqueEmojis" :key="emoji">{{ emoji }}</span>
      </span>
      <span>{{ totalCount }}</span>
    </button>
    <div
      v-if="showPopover"
      v-on-click-outside="closePopover"
      class="absolute bottom-full z-50 mb-1 min-w-48 rounded-lg border border-n-slate-6 bg-n-solid-2 p-2 shadow-lg"
      :class="alignment === 'right' ? 'right-0' : 'left-0'"
    >
      <div
        v-for="(group, groupIdx) in groupedReactions"
        :key="group.emoji"
        :class="{ 'mt-2 border-t border-n-slate-5 pt-2': groupIdx > 0 }"
      >
        <component
          :is="user.isMine && !readOnly ? 'button' : 'div'"
          v-for="(user, userIdx) in group.users"
          :key="`${group.emoji}-${user.id ?? userIdx}`"
          :type="user.isMine && !readOnly ? 'button' : null"
          class="flex w-full items-center gap-2 rounded px-1 py-1 text-left"
          :class="
            user.isMine && !readOnly ? 'cursor-pointer hover:bg-n-alpha-2' : ''
          "
          @click="handleRowClick(group.emoji, user)"
        >
          <span class="w-5 text-center text-sm">{{ group.emoji }}</span>
          <div class="flex-1 min-w-0">
            <div class="text-xs text-n-slate-12 truncate">
              {{ user.isMine ? t('CONVERSATION.REACTIONS.YOU') : user.name }}
            </div>
            <div
              v-if="user.isMine && !readOnly"
              class="text-[10px] text-n-slate-11"
            >
              {{ t('CONVERSATION.REACTIONS.CLICK_TO_REMOVE') }}
            </div>
          </div>
        </component>
      </div>
    </div>
  </div>
</template>
