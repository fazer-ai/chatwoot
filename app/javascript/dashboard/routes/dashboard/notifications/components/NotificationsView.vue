<script>
import { mapGetters } from 'vuex';
import { useTrack } from 'dashboard/composables';
import TableFooter from 'dashboard/components/widgets/TableFooter.vue';

import NotificationTable from './NotificationTable.vue';

import { ACCOUNT_EVENTS } from '../../../../helper/AnalyticsHelper/events';
export default {
  components: {
    NotificationTable,
    TableFooter,
  },
  computed: {
    ...mapGetters({
      accountId: 'getCurrentAccountId',
      meta: 'notifications/getMeta',
      records: 'notifications/getNotifications',
      uiFlags: 'notifications/getUIFlags',
    }),
  },
  mounted() {
    this.$store.dispatch('notifications/get', { page: 1 });
  },
  methods: {
    onPageChange(page) {
      window.history.pushState({}, null, `${this.$route.path}?page=${page}`);
      this.$store.dispatch('notifications/get', { page });
    },
    openNotification(notification) {
      const {
        primary_actor_id: primaryActorId,
        primary_actor_type: primaryActorType,
        primary_actor: primaryActor,
        notification_type: notificationType,
      } = notification;

      useTrack(ACCOUNT_EVENTS.OPEN_CONVERSATION_VIA_NOTIFICATION, {
        notificationType,
      });
      this.$store.dispatch('notifications/read', {
        id: notification.id,
        primaryActorId,
        primaryActorType,
        unreadCount: this.meta.unreadCount,
      });

      if (!primaryActor) return;

      if (notificationType.startsWith('internal_chat')) {
        this.$router.push({
          name:
            primaryActor.channel_type === 'dm'
              ? 'internal_chat_dm'
              : 'internal_chat_channel',
          params: {
            accountId: this.accountId,
            channelId: primaryActor.id,
          },
        });
        return;
      }

      this.$router.push(
        `/app/accounts/${this.accountId}/conversations/${primaryActor.id}`
      );
    },
    onMarkAllDoneClick() {
      useTrack(ACCOUNT_EVENTS.MARK_AS_READ_NOTIFICATIONS);
      this.$store.dispatch('notifications/readAll');
    },
  },
};
</script>

<template>
  <div class="h-full overflow-y-auto">
    <div class="flex flex-col h-full">
      <NotificationTable
        :notifications="records"
        :is-loading="uiFlags.isFetching"
        :is-updating="uiFlags.isUpdating"
        :on-click-notification="openNotification"
        :on-mark-all-done-click="onMarkAllDoneClick"
      />
      <TableFooter
        class="border-t border-n-weak"
        :current-page="Number(meta.currentPage)"
        :total-count="meta.count"
        :page-size="15"
        @page-change="onPageChange"
      />
    </div>
  </div>
</template>
