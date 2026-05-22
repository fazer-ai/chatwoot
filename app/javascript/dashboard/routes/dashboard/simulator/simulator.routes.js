import { frontendURL } from '../../../helper/URLHelper';
import SimulatorIndex from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/simulator'),
      name: 'simulator',
      meta: {
        permissions: ['administrator', 'agent', 'custom_role'],
      },
      component: SimulatorIndex,
    },
  ],
};
