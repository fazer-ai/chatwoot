import { test, expect } from '@playwright/test';
import {
  login,
  createChannelViaAPI,
  sendMessageViaAPI,
} from '../helpers/auth';

test.describe('Internal Chat - Threads', () => {
  let channelId: number;
  let accountId: number;
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

    await page.goto(
      `${baseURL}/app/accounts/${accountId}/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // Hover over the message to show action buttons
    const messageBubble = page
      .locator('.group')
      .filter({ hasText: messageText });
    await messageBubble.hover();

    // Click the reply button (title = "Responder" in pt_BR)
    const replyButton = messageBubble.locator('button[title="Responder"]');
    await expect(replyButton).toBeVisible();
    await replyButton.click();

    // ThreadPanel.vue opens - it has class w-96 and an h3 with "Conversa" (pt_BR for Thread)
    const threadPanel = page.locator('.w-96');
    await expect(threadPanel).toBeVisible();

    const threadTitle = threadPanel.locator('h3');
    await expect(threadTitle).toContainText('Conversa');

    // The thread panel should show the parent message
    const parentInThread = threadPanel.getByText(messageText);
    await expect(parentInThread).toBeVisible();

    // The thread panel has a reply textarea with placeholder
    // "Responder na conversa..." (pt_BR)
    const threadInput = threadPanel.locator('textarea');
    await expect(threadInput).toBeVisible();
  });

  test('send a reply in thread', async ({ page }) => {
    const messageText = `Thread reply test ${Date.now()}`;
    await sendMessageViaAPI(page, channelId, messageText);

    await page.goto(
      `${baseURL}/app/accounts/${accountId}/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // Open thread
    const messageBubble = page
      .locator('.group')
      .filter({ hasText: messageText });
    await messageBubble.hover();
    const replyButton = messageBubble.locator('button[title="Responder"]');
    await replyButton.click();

    // Type a reply in the thread
    const threadPanel = page.locator('.w-96');
    const threadInput = threadPanel.locator('textarea');
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

    await page.goto(
      `${baseURL}/app/accounts/${accountId}/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // Open thread
    const messageBubble = page
      .locator('.group')
      .filter({ hasText: messageText });
    await messageBubble.hover();
    const replyButton = messageBubble.locator('button[title="Responder"]');
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
});
