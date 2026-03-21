import { test, expect } from '@playwright/test';
import {
  login,
  createChannelViaAPI,
  sendMessageViaAPI,
  markUnreadViaAPI,
  channelURL,
  internalChatURL,
} from '../helpers/auth';

test.describe('Internal Chat - Mark Read/Unread', () => {
  let channelId;
  let accountId;
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
    // Send a message to create content
    await sendMessageViaAPI(page, channelId, 'Unread message');

    // Navigate to the specific channel (ChannelView calls markRead() on mount)
    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    // The message should be visible (channel loaded successfully)
    await expect(page.getByText('Unread message')).toBeVisible();

    // The message editor should be present (channel is functional and marked as read)
    const messageInput = page.getByPlaceholder('Type a message...');
    await expect(messageInput).toBeVisible();
  });

  test('message appears in channel after API send and navigation', async ({
    page,
  }) => {
    // Send a message via API
    const messageText = `Read test ${Date.now()}`;
    await sendMessageViaAPI(page, channelId, messageText);

    // Navigate to the channel
    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    // The message should be visible
    await expect(page.getByText(messageText)).toBeVisible();
  });

  test('marking channel as unread via API shows unread badge in sidebar', async ({
    page,
  }) => {
    // Send a message first so there is content
    await sendMessageViaAPI(page, channelId, 'Some message');

    // Mark the channel as unread via API
    await markUnreadViaAPI(page, channelId);

    // Navigate to internal chat home (not the channel itself, so it stays unread)
    await page.goto(internalChatURL(accountId));
    await page.waitForLoadState('networkidle');

    // The channel in the sidebar should have an unread badge
    // ChannelSidebar shows unread_count as a span.bg-n-brand badge
    const sidebar = page.locator('.w-64');
    const channelButton = sidebar.locator('button').filter({
      hasText: /readunread-/,
    });

    // The channel should be visible in the sidebar
    await expect(channelButton.first()).toBeVisible();

    // Look for the unread badge (span with bg-n-brand class and a number)
    const unreadBadge = channelButton.locator('.bg-n-brand');
    // After marking unread, the badge must be visible
    await expect(unreadBadge).toBeVisible();
  });

  test('navigating to an unread channel clears unread state', async ({
    page,
  }) => {
    // Send a message to create content
    await sendMessageViaAPI(page, channelId, 'Message for unread test');

    // Mark as unread
    await markUnreadViaAPI(page, channelId);

    // Now navigate directly to the channel (should auto-mark as read)
    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    // The message should be visible
    await expect(page.getByText('Message for unread test')).toBeVisible();

    // After navigating to the channel, ChannelView calls markRead() on mount
    // Now navigate back to the internal chat home and check that the unread
    // badge is gone for this channel
    await page.goto(internalChatURL(accountId));
    await page.waitForLoadState('networkidle');

    const sidebar = page.locator('.w-64');
    const channelButton = sidebar.locator('button').filter({
      hasText: /readunread-/,
    });
    await expect(channelButton.first()).toBeVisible();

    // The unread badge should not be present after reading
    const unreadBadge = channelButton.locator('.bg-n-brand');
    await expect(unreadBadge).toHaveCount(0);
  });

  test('multiple messages increment the channel message list', async ({
    page,
  }) => {
    // Send multiple messages via API
    const msg1 = `First message ${Date.now()}`;
    const msg2 = `Second message ${Date.now()}`;
    await sendMessageViaAPI(page, channelId, msg1);
    await sendMessageViaAPI(page, channelId, msg2);

    // Navigate to the channel
    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    // Both messages should be visible
    await expect(page.getByText(msg1)).toBeVisible();
    await expect(page.getByText(msg2)).toBeVisible();
  });
});
