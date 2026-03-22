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
      class="absolute bottom-full left-0 z-50 mb-1 min-w-48 max-w-64 rounded-lg border border-n-slate-6 bg-n-solid-2 p-3 shadow-lg"
    >
      <div
        v-for="group in groupedReactions"
        :key="group.emoji"
        class="mb-2 last:mb-0"
      >
        <div class="mb-1 flex items-center gap-1.5">
          <span class="text-base">{{ group.emoji }}</span>
          <span class="text-xs font-medium text-n-slate-10">
            {{ group.count }}
          </span>
        </div>
        <div class="space-y-0.5 pl-1">
          <div
            v-for="user in group.users"
            :key="user.reactionId"
            class="flex items-center justify-between gap-2"
          >
            <span class="truncate text-xs text-n-slate-12">
              {{ user.name }}
            </span>
            <button
              v-if="user.id === currentUserId"
              type="button"
              class="flex-shrink-0 rounded p-0.5 text-n-slate-9 hover:bg-n-ruby-3 hover:text-n-ruby-11"
              :title="t('INTERNAL_CHAT.MESSAGE.DELETE')"
              @click.stop="handleRemove(user.reactionId)"
            >
              <Icon icon="i-lucide-x" class="size-3" />
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
