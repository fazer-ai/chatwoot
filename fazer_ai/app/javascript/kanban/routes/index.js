import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { frontendURL } from 'dashboard/helper/URLHelper';
import KanbanBoardPage from 'kanban/pages/KanbanBoardPage.vue';
import KanbanBoardSettingsPage from 'kanban/pages/KanbanBoardSettingsPage.vue';
import KanbanOverviewPage from 'kanban/pages/KanbanOverviewPage.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/kanban/overview'),
    component: KanbanOverviewPage,
    name: 'kanban_list',
    meta: {
      permissions: ['administrator', 'agent'],
      // Note: No featureFlag here - the page handles displaying a disabled state
    },
  },
  {
    path: frontendURL('accounts/:accountId/kanban/:boardId/settings'),
    component: KanbanBoardSettingsPage,
    name: 'kanban_board_settings',
    meta: {
      permissions: ['administrator', 'agent'],
      featureFlag: FEATURE_FLAGS.KANBAN,
    },
  },
  {
    path: frontendURL('accounts/:accountId/kanban/:boardId?'),
    component: KanbanBoardPage,
    name: 'kanban_board_show',
    meta: {
      permissions: ['administrator', 'agent'],
      featureFlag: FEATURE_FLAGS.KANBAN,
    },
    children: [
      {
        path: 'create',
        name: 'kanban_task_create',
        component: KanbanBoardPage,
        meta: {
          permissions: ['administrator', 'agent'],
          featureFlag: FEATURE_FLAGS.KANBAN,
        },
      },
      {
        path: 'task/:taskId',
        name: 'kanban_task_show',
        component: KanbanBoardPage,
        meta: {
          permissions: ['administrator', 'agent'],
          featureFlag: FEATURE_FLAGS.KANBAN,
        },
      },
    ],
  },
];
