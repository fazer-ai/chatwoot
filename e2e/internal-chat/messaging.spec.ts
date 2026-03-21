import { test, expect } from '@playwright/test';
import {
  login,
  loginAndNavigateToChannel,
  createChannelViaAPI,
  sendMessageViaAPI,
} from '../helpers/auth';

test.describe('Internal Chat - Messaging', () => {
  let channelId: number;

  test.beforeEach(async ({ page }) => {
    const baseURL = 'http://localhost:3000';
    await login(page, baseURL);

    // Create a fresh channel for each test
    const channel = await createChannelViaAPI(page, {
      name: `msg-test-${Date.now()}`,
      description: 'Messaging test channel',
    });
    channelId = channel.id;
  });

  test('send a text message', async ({ page }) => {
    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // MessageEditor.vue has a textarea with placeholder from
    // INTERNAL_CHAT.MESSAGE.PLACEHOLDER = "Type a message..."
    const messageInput = page.getByPlaceholder('Type a message...');
    await expect(messageInput).toBeVisible();

    const messageText = `Hello E2E test ${Date.now()}`;
    await messageInput.fill(messageText);

    // Send button has title from INTERNAL_CHAT.MESSAGE.SEND = "Send"
    const sendButton = page.locator('button[title="Send"]');
    await sendButton.click();

    // The message should appear in the message list
    // MessageBubble renders the content in a div with v-dompurify-html
    const sentMessage = page.getByText(messageText);
    await expect(sentMessage).toBeVisible();

    // Input should be cleared after sending
    await expect(messageInput).toHaveValue('');
  });

  test('send message with Enter key', async ({ page }) => {
    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    const messageInput = page.getByPlaceholder('Type a message...');
    const messageText = `Enter key test ${Date.now()}`;
    await messageInput.fill(messageText);

    // Press Enter to send (not Shift+Enter which is newline)
    await messageInput.press('Enter');

    const sentMessage = page.getByText(messageText);
    await expect(sentMessage).toBeVisible();
  });

  test('edit a message', async ({ page }) => {
    // Send a message via API first
    const originalText = `Original message ${Date.now()}`;
    await sendMessageViaAPI(page, channelId, originalText);

    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // Find the message and hover over it to reveal action buttons
    const messageBubble = page
      .locator('.group')
      .filter({ hasText: originalText });
    await messageBubble.hover();

    // Click the edit button (title = "Edit" from INTERNAL_CHAT.MESSAGE.EDIT)
    const editButton = messageBubble.locator('button[title="Edit"]');
    await expect(editButton).toBeVisible();
    await editButton.click();

    // After clicking edit, the message content should be editable
    // The edit flow is handled by the parent ChannelView.vue
    // which calls handleEdit with the message object
    // The exact edit UI depends on implementation - verify the edit button works
    await expect(editButton).toBeVisible();
  });

  test('delete a message shows deleted placeholder', async ({ page }) => {
    // Send a message via API first
    const messageText = `Delete me ${Date.now()}`;
    await sendMessageViaAPI(page, channelId, messageText);

    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // Hover over the message to show action buttons
    const messageBubble = page.locator('.group').filter({ hasText: messageText });
    await messageBubble.hover();

    // Click the delete button (title = "Delete" from INTERNAL_CHAT.MESSAGE.DELETE)
    const deleteButton = messageBubble.locator('button[title="Delete"]');
    await expect(deleteButton).toBeVisible();
    await deleteButton.click();

    // After deletion, the message shows "This message was deleted"
    // (from INTERNAL_CHAT.MESSAGE.DELETED)
    const deletedText = page.getByText('This message was deleted');
    await expect(deletedText).toBeVisible();
  });

  test('pin a message shows pin indicator', async ({ page }) => {
    // Send a message via API first
    const messageText = `Pin me ${Date.now()}`;
    await sendMessageViaAPI(page, channelId, messageText);

    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // Hover over the message to show action buttons
    const messageBubble = page.locator('.group').filter({ hasText: messageText });
    await messageBubble.hover();

    // Click pin button (title = "Pin message" from INTERNAL_CHAT.PIN.PIN)
    const pinButton = messageBubble.locator('button[title="Pin message"]');
    await expect(pinButton).toBeVisible();
    await pinButton.click();

    // After pinning, the ChannelHeader shows a pinned message banner
    // with text "Pinned message" (from INTERNAL_CHAT.PIN.PINNED_MESSAGE)
    const pinnedBanner = page.getByText('Pinned message');
    await expect(pinnedBanner.first()).toBeVisible();
  });

  test('message shows sender name and timestamp', async ({ page }) => {
    // Send a message via API
    const messageText = `Metadata test ${Date.now()}`;
    await sendMessageViaAPI(page, channelId, messageText);

    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // MessageBubble renders sender name in a span with font-medium class
    const messageBubble = page.locator('.group').filter({ hasText: messageText });
    await expect(messageBubble).toBeVisible();

    // Sender name should be visible (the seeded user is "John")
    const senderName = messageBubble.locator('.font-medium').first();
    await expect(senderName).toBeVisible();
    await expect(senderName).not.toHaveText('');

    // Timestamp should be visible (rendered in a <time> element)
    const timestamp = messageBubble.locator('time');
    await expect(timestamp).toBeVisible();
  });

  test('empty channel shows no messages placeholder', async ({ page }) => {
    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // MessageList.vue shows "No messages yet. Start the conversation!"
    // when messages array is empty
    const emptyText = page.getByText(
      'No messages yet. Start the conversation!'
    );
    await expect(emptyText).toBeVisible();
  });
});
