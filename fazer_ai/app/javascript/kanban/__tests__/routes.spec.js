import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { describe, expect, it } from 'vitest';
import { routes } from 'kanban/routes';
import { frontendURL } from 'dashboard/helper/URLHelper';

describe('Kanban routes', () => {
  it('registers kanban routes with correct meta', () => {
    const overviewRoute = routes.find(r => r.name === 'kanban_list');
    const boardRoute = routes.find(r => r.name === 'kanban_board_show');

    expect(overviewRoute).toBeDefined();

    expect(boardRoute).toBeDefined();
    expect(boardRoute.meta.featureFlag).toBe(FEATURE_FLAGS.KANBAN);
    expect(boardRoute.path).toBe(
      frontendURL('accounts/:accountId/kanban/:boardId?')
    );
  });
});
