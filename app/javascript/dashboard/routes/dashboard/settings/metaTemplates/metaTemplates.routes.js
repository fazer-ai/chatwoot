import { frontendURL } from '../../../../helper/URLHelper';

import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';

// Access is open to every non-portal role. Agents get the read-only list
// (Fatia 2 renders the disabled action buttons for them); managers and
// administrators can also create/edit/delete once Fatia 3+ ship.
// The sidebar link itself is gated on the account having at least one
// Cloud WhatsApp inbox (see Sidebar.vue), so agents on Baileys-only
// accounts never see the menu even though the route would authorize them.
const PERMISSIONS = ['administrator', 'agent', 'manager', 'custom_role'];

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/meta-templates'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'meta_templates_index',
          meta: {
            permissions: PERMISSIONS,
          },
          component: Index,
        },
      ],
    },
  ],
};
