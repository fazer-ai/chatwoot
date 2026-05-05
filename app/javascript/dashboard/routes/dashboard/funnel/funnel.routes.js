import store from 'dashboard/store';
import { frontendURL } from 'dashboard/helper/URLHelper';
import FunnelIndex from './Index.vue';

const funnelRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/funnel'),
      name: 'funnel_index',
      component: FunnelIndex,
      meta: {
        permissions: ['administrator', 'manager', 'agent'],
      },
      beforeEnter: (to, from, next) => {
        const accountId = Number(to.params.accountId);
        const account = store.getters['accounts/getAccount'](accountId);
        if (account?.funnel_enabled === false) {
          next({ name: 'home', params: { accountId } });
          return;
        }
        next();
      },
    },
  ],
};

export default funnelRoutes;
