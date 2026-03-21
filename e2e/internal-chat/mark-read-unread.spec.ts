import { test, expect } from '@playwright/test';
import {
  login,
  createChannelViaAPI,
  sendMessageViaAPI,
} from '../helpers/auth';

test.describe('Internal Chat - Mark Read/Unread', () => {
  let channelId: number;

  test.beforeEach(async ({ page }) => {
    const baseURL = 'http://localhost:3000';
    await login(page, baseURL);

    const channel = await createChannelViaAPI(page, {
      name: `readunread-test-${Date.now()}`,
    });
    channelId = channel.id;
  });

  test('channel marks as read when navigated to', async ({ page }) => {
    // Send a message to create an unread state
    await sendMessageViaAPI(page, channelId, 'Unread message');

    // Navigate to the internal chat home first (channel not selected)
    await page.goto('http://localhost:3000/app/accounts/1/internal-chat');
    await page.waitForLoadState('networkidle');

    // Navigate to the specific channel
    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // ChannelView.vue calls markRead() on mount, so the unread_count
    // should be set to 0. The sidebar should not show an unread badge
    // for this channel anymore.
    // Navigate back to home to check the sidebar state
    await page.goto('http://localhost:3000/app/accounts/1/internal-chat');
    await page.waitForLoadState('networkidle');

    // Find the channel button - it should NOT have an unread count badge
    // Unread badge is rendered as a span with rounded-full bg-n-brand
    // inside the channel button
    const channelButton = page
      .locator('.flex-1.overflow-y-auto')
      .getByRole('button')
      .filter({ hasText: /readunread-test/ });

    // If it exists, check it doesn't have the badge
    const badge = channelButton.locator(
      '.rounded-full.bg-n-brand'
    );
    await expect(badge).toHaveCount(0);
  });

  test('mark channel as unread via API and see unread badge', async ({
    page,
  }) => {
    // Send a message
    const msg = await sendMessageViaAPI(
      page,
      channelId,
      'Mark unread test message'
    );

    // First mark it as read
    await page.request.post(
      `http://localhost:3000/api/v1/accounts/1/internal_chat/channels/${channelId}/mark_read`
    );

    // Then mark it as unread
    await page.request.post(
      `http://localhost:3000/api/v1/accounts/1/internal_chat/channels/${channelId}/mark_unread`,
      { data: { message_id: msg.id } }
    );

    // Navigate to internal chat to see the sidebar
    await page.goto('http://localhost:3000/app/accounts/1/internal-chat');
    await page.waitForLoadState('networkidle');

    // The channel should show an unread badge
    // ChannelSidebar renders unread_count > 0 as a span with
    // rounded-full bg-n-brand classes
    const channelButton = page
      .locator('.flex-1.overflow-y-auto')
      .getByRole('button')
      .filter({ hasText: /readunread-test/ });

    const badge = channelButton.locator(
      '.rounded-full.bg-n-brand'
    );
    await expect(badge.first()).toBeVisible();
  });

  test('navigating to channel with unread clears the badge', async ({
    page,
  }) => {
    // Send a message and mark as unread
    const msg = await sendMessageViaAPI(
      page,
      channelId,
      'Navigate to clear test'
    );

    await page.request.post(
      `http://localhost:3000/api/v1/accounts/1/internal_chat/channels/${channelId}/mark_unread`,
      { data: { message_id: msg.id } }
    );

    // Navigate to internal chat home
    await page.goto('http://localhost:3000/app/accounts/1/internal-chat');
    await page.waitForLoadState('networkidle');

    // Verify unread badge exists
    const channelButton = page
      .locator('.flex-1.overflow-y-auto')
      .getByRole('button')
      .filter({ hasText: /readunread-test/ });

    const badge = channelButton.locator(
      '.rounded-full.bg-n-brand'
    );
    await expect(badge.first()).toBeVisible();

    // Click the channel to navigate to it
    await channelButton.click();
    await page.waitForLoadState('networkidle');

    // Go back to the sidebar view and verify badge is gone
    // Since ChannelView calls markRead on mount, the channel should be read
    await page.goto('http://localhost:3000/app/accounts/1/internal-chat');
    await page.waitForLoadState('networkidle');

    const channelButtonAfter = page
      .locator('.flex-1.overflow-y-auto')
      .getByRole('button')
      .filter({ hasText: /readunread-test/ });

    const badgeAfter = channelButtonAfter.locator(
      '.rounded-full.bg-n-brand'
    );
    await expect(badgeAfter).toHaveCount(0);
  });
});
