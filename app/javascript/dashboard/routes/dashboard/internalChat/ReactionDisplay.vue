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
});

const emit = defineEmits(['remove']);

const { t } = useI18n();

const showPopover = ref(false);

const groupedReactions = computed(() => {
  const groups = {};
  props.reactions.forEach(reaction => {
    if (!groups[reaction.emoji]) {
      groups[reaction.emoji] = {
        emoji: reaction.emoji,
        count: 0,
        userReactionId: null,
        users: [],
      };
    }
    const isMine = reaction.user_id === props.currentUserId;
    groups[reaction.emoji].count += 1;
    groups[reaction.emoji].users.push({
      name: reaction.user?.name || '',
      reactionId: reaction.id,
      isMine,
    });
    if (isMine) {
      groups[reaction.emoji].userReactionId = reaction.id;
    }
  });
  return Object.values(groups);
});

function togglePopover() {
  showPopover.value = !showPopover.value;
}

function closePopover() {
  showPopover.value = false;
}

function handleRowClick(user) {
  if (!user.isMine) return;
  emit('remove', user.reactionId);
  // `reactions.length` is still the pre-removal count here. Close when the
  // post-removal state would leave at most one reaction left: at that point
  // the popover's list view collapses to a single user and stops being
  // useful, so dropping it avoids a dangling open panel.
  if (props.reactions.length - 1 <= 1) closePopover();
}
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div
    v-if="groupedReactions.length"
    class="relative mt-1 flex flex-wrap items-center gap-1"
  >
    <button
      v-for="group in groupedReactions"
      :key="group.emoji"
      type="button"
      class="inline-flex items-center gap-1 rounded-full border px-1.5 py-0.5 text-xs transition-colors"
      :class="
        group.userReactionId
          ? 'border-n-brand bg-n-alpha-2 text-n-brand'
          : 'border-n-slate-6 bg-n-alpha-1 text-n-slate-12 hover:bg-n-alpha-2'
      "
      @click="togglePopover"
    >
      <span>{{ group.emoji }}</span>
      <span>{{ group.count }}</span>
    </button>
    <div
      v-if="showPopover"
      v-on-click-outside="closePopover"
      class="absolute bottom-full left-0 z-50 mb-1 min-w-48 rounded-lg border border-n-slate-6 bg-n-solid-2 p-2 shadow-lg"
    >
      <div
        v-for="(group, groupIdx) in groupedReactions"
        :key="group.emoji"
        :class="{ 'mt-2 border-t border-n-slate-5 pt-2': groupIdx > 0 }"
      >
        <component
          :is="user.isMine ? 'button' : 'div'"
          v-for="user in group.users"
          :key="user.reactionId"
          :type="user.isMine ? 'button' : null"
          class="flex w-full items-center gap-2 rounded px-1 py-1 text-left"
          :class="user.isMine ? 'cursor-pointer hover:bg-n-alpha-2' : ''"
          @click="handleRowClick(user)"
        >
          <span class="w-5 text-center text-sm">{{ group.emoji }}</span>
          <div class="flex-1 min-w-0">
            <div class="text-xs text-n-slate-12 truncate">
              {{ user.isMine ? t('CONVERSATION.REACTIONS.YOU') : user.name }}
            </div>
            <div v-if="user.isMine" class="text-[10px] text-n-slate-11">
              {{ t('CONVERSATION.REACTIONS.CLICK_TO_REMOVE') }}
            </div>
          </div>
        </component>
      </div>
    </div>
  </div>
</template>
