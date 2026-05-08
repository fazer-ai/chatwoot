import { frontendURL } from 'dashboard/helper/URLHelper';
import ReleaseNotesIndex from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/release-notes'),
      name: 'release_notes_index',
      component: ReleaseNotesIndex,
      meta: {
        permissions: ['administrator', 'manager', 'agent'],
      },
    },
  ],
};
