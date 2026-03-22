<script setup>
import { computed } from 'vue';

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

const emit = defineEmits(['add', 'remove']);

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
    groups[reaction.emoji].count += 1;
    groups[reaction.emoji].users.push(reaction.user);
    if (reaction.user_id === props.currentUserId) {
      groups[reaction.emoji].userReactionId = reaction.id;
    }
  });
  return Object.values(groups);
});

function handleClick(group) {
  if (group.userReactionId) {
    emit('remove', group.userReactionId);
  } else {
    emit('add', group.emoji);
  }
}
</script>

<template>
  <div class="flex flex-wrap items-center gap-1 mt-1">
    <button
      v-for="group in groupedReactions"
      :key="group.emoji"
      class="inline-flex items-center gap-1 px-1.5 py-0.5 text-xs rounded-full border transition-colors"
      :class="
        group.userReactionId
          ? 'border-n-brand bg-n-alpha-2 text-n-brand'
          : 'border-n-slate-6 bg-n-alpha-1 text-n-slate-12 hover:bg-n-alpha-2'
      "
      :title="
        group.users
          .map(u => u?.name || '')
          .filter(Boolean)
          .join(', ')
      "
      @click="handleClick(group)"
    >
      <span>{{ group.emoji }}</span>
      <span>{{ group.count }}</span>
    </button>
  </div>
</template>
