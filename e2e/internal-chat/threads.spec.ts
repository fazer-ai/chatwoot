import { test, expect } from '@playwright/test';
import {
  login,
  createChannelViaAPI,
  sendMessageViaAPI,
  sendThreadReplyViaAPI,
  channelURL,
} from '../helpers/auth';

test.describe('Internal Chat - Threads', () => {
  let channelId;
  let accountId;
  const baseURL = 'http://localhost:3000';

  test.beforeEach(async ({ page }) => {
    const { data } = await login(page, baseURL);
    accountId = data.account_id;

    const channel = await createChannelViaAPI(page, {
      name: `thread-${Date.now()}`,
    });
    channelId = channel.id;
  });

  test('reply button opens thread panel', async ({ page }) => {
    const messageText = `Thread parent ${Date.now()}`;
    await sendMessageViaAPI(page, channelId, messageText);

    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    // Hover over the message to show action buttons
    const messageBubble = page
      .locator('.group')
      .filter({ hasText: messageText });
    await messageBubble.hover();

    // Click the reply button (title = "Reply" from INTERNAL_CHAT.MESSAGE.REPLY)
    const replyButton = messageBubble.locator('button[title="Reply"]');
    await expect(replyButton).toBeVisible();
    await replyButton.click();

    // ThreadPanel.vue opens with class w-96 and an h3 containing "Thread"
    // (INTERNAL_CHAT.THREAD.TITLE)
    const threadPanel = page.locator('.w-96');
    await expect(threadPanel).toBeVisible();

    const threadTitle = threadPanel.locator('h3');
    await expect(threadTitle).toContainText('Thread');

    // The thread panel should show the parent message
    const parentInThread = threadPanel.getByText(messageText);
    await expect(parentInThread).toBeVisible();

    // The thread panel has a reply textarea with placeholder
    // "Reply in thread..." (INTERNAL_CHAT.THREAD.REPLY_PLACEHOLDER)
    const threadInput = threadPanel.getByPlaceholder('Reply in thread...');
    await expect(threadInput).toBeVisible();
  });

  test('send a reply in thread', async ({ page }) => {
    const messageText = `Thread reply test ${Date.now()}`;
    await sendMessageViaAPI(page, channelId, messageText);

    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    // Open thread
    const messageBubble = page
      .locator('.group')
      .filter({ hasText: messageText });
    await messageBubble.hover();
    const replyButton = messageBubble.locator('button[title="Reply"]');
    await replyButton.click();

    // Type a reply in the thread
    const threadPanel = page.locator('.w-96');
    const threadInput = threadPanel.getByPlaceholder('Reply in thread...');
    await expect(threadInput).toBeVisible();

    const replyText = `Thread reply ${Date.now()}`;
    await threadInput.fill(replyText);
    await threadInput.press('Enter');

    // Reply should appear in the thread panel
    const replyMessage = threadPanel.getByText(replyText);
    await expect(replyMessage).toBeVisible();
  });

  test('close thread panel', async ({ page }) => {
    const messageText = `Close thread ${Date.now()}`;
    await sendMessageViaAPI(page, channelId, messageText);

    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    // Open thread
    const messageBubble = page
      .locator('.group')
      .filter({ hasText: messageText });
    await messageBubble.hover();
    const replyButton = messageBubble.locator('button[title="Reply"]');
    await replyButton.click();

    // Thread panel should be open
    const threadPanel = page.locator('.w-96');
    await expect(threadPanel).toBeVisible();

    // Close button is in ThreadPanel header (icon i-lucide-x)
    const closeButton = threadPanel.locator('button:has(.i-lucide-x)');
    await closeButton.click();

    // Thread panel should be hidden
    await expect(threadPanel).toHaveCount(0);
  });

  test('thread reply count badge shown on parent message', async ({ page }) => {
    const messageText = `Reply count test ${Date.now()}`;
    const msg = await sendMessageViaAPI(page, channelId, messageText);

    // Send a thread reply via API
    await sendThreadReplyViaAPI(page, channelId, msg.id, 'Thread reply 1');

    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    // The parent message should show the reply count button
    // MessageBubble renders: "{count} replies" button with i-lucide-message-square icon
    const messageBubble = page
      .locator('.group')
      .filter({ hasText: messageText });
    await expect(messageBubble).toBeVisible();

    const replyCountButton = messageBubble.locator(
      'button:has(.i-lucide-message-square)'
    );
    await expect(replyCountButton).toBeVisible();
    // Should contain "replies" text
    await expect(replyCountButton).toContainText('replies');
  });

  test('clicking reply count opens thread panel', async ({ page }) => {
    const messageText = `Open thread via count ${Date.now()}`;
    const msg = await sendMessageViaAPI(page, channelId, messageText);

    await sendThreadReplyViaAPI(page, channelId, msg.id, 'A reply');

    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    const messageBubble = page
      .locator('.group')
      .filter({ hasText: messageText });
    const replyCountButton = messageBubble.locator(
      'button:has(.i-lucide-message-square)'
    );
    await expect(replyCountButton).toBeVisible();

    // Click the reply count button to open the thread
    await replyCountButton.click();

    // Thread panel should open showing the parent message and the reply
    const threadPanel = page.locator('.w-96');
    await expect(threadPanel).toBeVisible();
    await expect(threadPanel.getByText(messageText)).toBeVisible();
    await expect(threadPanel.getByText('A reply')).toBeVisible();
  });
});
