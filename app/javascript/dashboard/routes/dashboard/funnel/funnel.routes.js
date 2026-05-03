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
    },
  ],
};

export default funnelRoutes;
