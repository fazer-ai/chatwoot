import { frontendURL } from 'dashboard/helper/URLHelper.js';
import store from 'dashboard/store';

import DisparadorPageRouteView from './DisparadorPageRouteView.vue';
import Index from './Index.vue';
import Settings from './Settings.vue';

// Beta 0 "Disparador Cloud Shadow" is gated by the DISPARADOR_BETA0_VISIBLE
// installation config, exposed to the frontend via globalConfig. When the flag
// is off the route redirects to the dashboard (and the API 404s), so a deep
// link can never reach a broken page.
const ensureBeta0Visible = (to, from, next) => {
  if (store.getters['globalConfig/isDisparadorBeta0Visible']) {
    next();
  } else {
    next(frontendURL(`accounts/${to.params.accountId}/dashboard`));
  }
};

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/disparador'),
      component: DisparadorPageRouteView,
      children: [
        {
          path: '',
          name: 'disparador_wrapper',
          meta: {
            permissions: ['administrator'],
          },
          redirect: to => {
            return { name: 'disparador_list', params: to.params };
          },
        },
        {
          path: 'list',
          name: 'disparador_list',
          meta: {
            permissions: ['administrator'],
          },
          beforeEnter: ensureBeta0Visible,
          component: Index,
        },
        {
          path: 'settings',
          name: 'disparador_settings',
          meta: {
            permissions: ['administrator'],
          },
          beforeEnter: ensureBeta0Visible,
          component: Settings,
        },
      ],
    },
  ],
};
