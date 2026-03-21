<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  message: {
    type: Object,
    required: true,
  },
  isAdmin: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['vote', 'unvote']);

const { t } = useI18n();

const pollData = computed(() => {
  return props.message.poll || props.message.content_attributes?.poll || {};
});

const pollItems = computed(() => {
  return pollData.value.options || [];
});

const isMultipleChoice = computed(() => {
  return !!pollData.value.multiple_choice;
});

const isPublicResults = computed(() => {
  return pollData.value.public_results !== false;
});

const isExpired = computed(() => {
  const expiresAt = pollData.value.expires_at;
  if (!expiresAt) return false;
  return new Date(expiresAt) < new Date();
});

const totalVotes = computed(() => {
  return pollItems.value.reduce((sum, item) => {
    return sum + (item.votes_count || 0);
  }, 0);
});

const canSeeResults = computed(() => {
  return isPublicResults.value || props.isAdmin;
});

function hasUserVoted(item) {
  return !!item.voted;
}

function hasAnyVote() {
  return pollItems.value.some(item => item.voted);
}

function votePercentage(item) {
  if (totalVotes.value === 0) return 0;
  return Math.round(((item.votes_count || 0) / totalVotes.value) * 100);
}

function handleVote(item) {
  if (isExpired.value) return;

  if (hasUserVoted(item)) {
    emit('unvote', { messageId: props.message.id, optionId: item.id });
  } else {
    emit('vote', { messageId: props.message.id, optionId: item.id });
  }
}
</script>

<template>
  <div class="rounded-lg border border-n-slate-5 bg-n-solid-2 p-3">
    <div class="mb-3 flex items-start justify-between">
      <h4 class="text-sm font-semibold text-n-slate-12">
        {{ message.content }}
      </h4>
      <span
        v-if="isExpired"
        class="ml-2 flex-shrink-0 rounded bg-n-ruby-3 px-1.5 py-0.5 text-xs font-medium text-n-ruby-11"
      >
        {{ t('INTERNAL_CHAT.POLL.EXPIRED') }}
      </span>
    </div>

    <div class="space-y-2">
      <button
        v-for="item in pollItems"
        :key="item.id"
        class="group relative w-full overflow-hidden rounded-lg border p-2.5 text-left text-sm transition-colors"
        :class="[
          hasUserVoted(item)
            ? 'border-n-brand bg-n-brand/5'
            : 'border-n-slate-6 hover:border-n-slate-8',
          isExpired ? 'cursor-default' : 'cursor-pointer',
        ]"
        :disabled="isExpired"
        @click="handleVote(item)"
      >
        <div
          v-if="(hasAnyVote() || isExpired) && canSeeResults"
          class="absolute inset-0 rounded-lg bg-n-brand/10 transition-all"
          :style="{ width: `${votePercentage(item)}%` }"
        />
        <div class="relative flex items-center justify-between gap-2">
          <div class="flex items-center gap-2">
            <span
              v-if="hasUserVoted(item)"
              class="flex size-4 items-center justify-center rounded-full bg-n-brand"
            >
              <Icon icon="i-lucide-check" class="size-3 text-white" />
            </span>
            <span class="text-n-slate-12">{{ item.text }}</span>
          </div>
          <span
            v-if="(hasAnyVote() || isExpired) && canSeeResults"
            class="flex-shrink-0 text-xs text-n-slate-10"
          >
            {{
              t('INTERNAL_CHAT.POLL.PERCENTAGE', {
                value: votePercentage(item),
              })
            }}
          </span>
        </div>
      </button>
    </div>

    <div class="mt-2 flex items-center gap-2 text-xs text-n-slate-10">
      <span>
        {{ t('INTERNAL_CHAT.POLL.VOTES', { count: totalVotes }) }}
      </span>
      <span v-if="isMultipleChoice" class="text-n-slate-9">
        {{ t('INTERNAL_CHAT.POLL.MULTIPLE_CHOICE') }}
      </span>
    </div>
  </div>
</template>
