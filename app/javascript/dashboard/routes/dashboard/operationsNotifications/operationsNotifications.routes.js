import { frontendURL } from 'dashboard/helper/URLHelper';
import OperationsNotificationsIndex from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/operations-notifications'),
      name: 'operations_notifications_index',
      component: OperationsNotificationsIndex,
      meta: {
        permissions: ['administrator', 'manager', 'agent'],
      },
    },
  ],
};
