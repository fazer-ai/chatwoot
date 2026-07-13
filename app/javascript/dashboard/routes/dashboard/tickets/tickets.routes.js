import store from 'dashboard/store';
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
      beforeEnter: (to, from, next) => {
        const accountId = Number(to.params.accountId);
        const account = store.getters['accounts/getAccount'](accountId);
        if (account?.clickup_integration_enabled !== true) {
          next({ name: 'home', params: { accountId } });
          return;
        }
        next();
      },
    },
  ],
};
