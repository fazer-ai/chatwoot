import { frontendURL } from '../../../helper/URLHelper';
import TicketsIndex from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/tickets'),
      name: 'tickets_index',
      meta: {
        permissions: ['administrator', 'agent', 'custom_role'],
      },
      component: TicketsIndex,
    },
  ],
};
