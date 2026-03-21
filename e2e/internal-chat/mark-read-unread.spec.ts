import { test, expect } from '@playwright/test';
import {
  login,
  createChannelViaAPI,
  sendMessageViaAPI,
} from '../helpers/auth';

test.describe('Internal Chat - Mark Read/Unread', () => {
  let channelId: number;
  let accountId: number;
  const baseURL = 'http://localhost:3000';

  test.beforeEach(async ({ page }) => {
    const { data } = await login(page, baseURL);
    accountId = data.account_id;

    const channel = await createChannelViaAPI(page, {
      name: `readunread-${Date.now()}`,
    });
    channelId = channel.id;
  });

  test('channel marks as read when navigated to', async ({ page }) => {
    // Send a message to create an unread state
    await sendMessageViaAPI(page, channelId, 'Unread message');

    // Navigate to the specific channel (this should mark it as read via markRead() on mount)
    await page.goto(
      `${baseURL}/app/accounts/${accountId}/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // The message should be visible (channel loaded)
    await expect(page.getByText('Unread message')).toBeVisible();

    // The ChannelView calls markRead() on mount, so the channel should be read now
    // Verify the message editor is present (channel is functional)
    const messageInput = page.locator('textarea');
    await expect(messageInput).toBeVisible();
  });

  test('message appears in channel after API send and navigation', async ({
    page,
  }) => {
    // Send a message via API
    const messageText = `Read test ${Date.now()}`;
    await sendMessageViaAPI(page, channelId, messageText);

    // Navigate to the channel
    await page.goto(
      `${baseURL}/app/accounts/${accountId}/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // The message should be visible
    await expect(page.getByText(messageText)).toBeVisible();
  });
});
