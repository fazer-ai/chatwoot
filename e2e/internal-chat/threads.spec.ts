import { test, expect } from '@playwright/test';
import {
  login,
  createChannelViaAPI,
  sendMessageViaAPI,
} from '../helpers/auth';

test.describe('Internal Chat - Threads', () => {
  let channelId: number;

  test.beforeEach(async ({ page }) => {
    const baseURL = 'http://localhost:3000';
    await login(page, baseURL);

    const channel = await createChannelViaAPI(page, {
      name: `thread-test-${Date.now()}`,
    });
    channelId = channel.id;
  });

  test('reply button opens thread panel', async ({ page }) => {
    const messageText = `Thread parent ${Date.now()}`;
    await sendMessageViaAPI(page, channelId, messageText);

    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // Hover over the message to show action buttons
    const messageBubble = page.locator('.group').filter({ hasText: messageText });
    await messageBubble.hover();

    // Click the reply button (title = "Reply" from INTERNAL_CHAT.MESSAGE.REPLY)
    const replyButton = messageBubble.locator('button[title="Reply"]');
    await expect(replyButton).toBeVisible();
    await replyButton.click();

    // ThreadPanel.vue opens with heading "Thread"
    // (from INTERNAL_CHAT.THREAD.TITLE)
    const threadTitle = page.getByText('Thread', { exact: true });
    await expect(threadTitle.first()).toBeVisible();

    // The thread panel should show the parent message
    const parentInThread = page.locator('.w-96').getByText(messageText);
    await expect(parentInThread).toBeVisible();

    // The thread panel has a reply input with placeholder
    // from INTERNAL_CHAT.THREAD.REPLY_PLACEHOLDER = "Reply in thread..."
    const threadInput = page.getByPlaceholder('Reply in thread...');
    await expect(threadInput).toBeVisible();
  });

  test('send a reply in thread', async ({ page }) => {
    const messageText = `Thread reply test ${Date.now()}`;
    await sendMessageViaAPI(page, channelId, messageText);

    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // Open thread
    const messageBubble = page.locator('.group').filter({ hasText: messageText });
    await messageBubble.hover();
    const replyButton = messageBubble.locator('button[title="Reply"]');
    await replyButton.click();

    // Type a reply in the thread
    const threadInput = page.getByPlaceholder('Reply in thread...');
    await expect(threadInput).toBeVisible();

    const replyText = `Thread reply ${Date.now()}`;
    await threadInput.fill(replyText);
    await threadInput.press('Enter');

    // Reply should appear in the thread panel
    const replyMessage = page.locator('.w-96').getByText(replyText);
    await expect(replyMessage).toBeVisible();
  });

  test('thread reply count shows on parent message', async ({ page }) => {
    const messageText = `Reply count test ${Date.now()}`;
    const msg = await sendMessageViaAPI(page, channelId, messageText);

    // Send a reply via API to create a thread
    await page.request.post(
      `http://localhost:3000/api/v1/accounts/1/internal_chat/channels/${channelId}/messages`,
      { data: { content: 'A thread reply', parent_id: msg.id } }
    );

    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // MessageBubble shows thread reply count as a clickable button
    // with text like "1 replies" (from INTERNAL_CHAT.THREAD.REPLIES)
    const replyCountButton = page.locator('.group').filter({ hasText: messageText })
      .locator('button')
      .filter({ hasText: /repl/i });
    await expect(replyCountButton).toBeVisible();
  });

  test('close thread panel', async ({ page }) => {
    const messageText = `Close thread test ${Date.now()}`;
    await sendMessageViaAPI(page, channelId, messageText);

    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // Open thread
    const messageBubble = page.locator('.group').filter({ hasText: messageText });
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
});
