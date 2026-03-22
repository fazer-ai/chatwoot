<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import Icon from 'dashboard/components-next/icon/Icon.vue';

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
    groups[reaction.emoji].count += 1;
    groups[reaction.emoji].users.push({
      name: reaction.user?.name || '',
      id: reaction.user_id,
      reactionId: reaction.id,
    });
    if (reaction.user_id === props.currentUserId) {
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

function handleRemove(reactionId) {
  emit('remove', reactionId);
  if (props.reactions.length <= 1) {
    showPopover.value = false;
  }
}
</script>

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
        <div
          v-for="user in group.users"
          :key="user.reactionId"
          class="flex h-7 items-center gap-2 rounded px-1"
        >
          <span class="w-5 text-center text-sm">{{ group.emoji }}</span>
          <span class="flex-1 truncate text-xs text-n-slate-12">
            {{ user.name }}
          </span>
          <button
            v-if="user.id === currentUserId"
            type="button"
            class="flex-shrink-0 rounded p-1 text-n-slate-11 hover:bg-n-ruby-3 hover:text-n-ruby-11"
            :title="t('INTERNAL_CHAT.MESSAGE.DELETE')"
            @click.stop="handleRemove(user.reactionId)"
          >
            <Icon icon="i-lucide-x" class="size-4" />
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
