<script>
import { formatDate } from 'shared/helpers/DateHelper';

export default {
  props: {
    date: {
      type: String,
      required: true,
    },
  },
  computed: {
    formattedDate() {
      return formatDate({
        date: this.date,
        todayText: this.$t('TODAY'),
        yesterdayText: this.$t('YESTERDAY'),
      });
    },
  },
};
</script>

<template>
  <div class="flex justify-center w-full my-3">
    <span class="date-pill">{{ formattedDate }}</span>
  </div>
</template>

<style lang="scss" scoped>
.date-pill {
  background-color: #e1f3fb;
  color: #54656f;
  font-size: 0.75rem;
  font-weight: 500;
  padding: 0.3rem 0.75rem;
  border-radius: 0.5rem;
  box-shadow: 0 1px 0.5px rgba(0, 0, 0, 0.13);
}

:global(.dark) .date-pill,
:root[data-theme='dark'] .date-pill {
  background-color: #182229;
  color: #8696a0;
}
</style>
