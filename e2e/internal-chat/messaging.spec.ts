import { test, expect } from '@playwright/test';
import {
  login,
  createChannelViaAPI,
  sendMessageViaAPI,
  channelURL,
} from '../helpers/auth';

test.describe('Internal Chat - Messaging', () => {
  let channelId;
  let accountId;
  const baseURL = 'http://localhost:3000';

  test.beforeEach(async ({ page }) => {
    const { data } = await login(page, baseURL);
    accountId = data.account_id;

    const channel = await createChannelViaAPI(page, {
      name: `msg-test-${Date.now()}`,
      description: 'Messaging test channel',
    });
    channelId = channel.id;
  });

  test('send a text message via UI and verify it appears', async ({ page }) => {
    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    // MessageEditor.vue has a <textarea> with placeholder "Type a message..."
    const messageInput = page.getByPlaceholder('Type a message...');
    await expect(messageInput).toBeVisible();

    const messageText = `Hello E2E ${Date.now()}`;
    await messageInput.fill(messageText);

    // Click the send button (has title "Send" from INTERNAL_CHAT.MESSAGE.SEND)
    const sendButton = page.locator('button[title="Send"]');
    await sendButton.click();

    // The message should appear in the message list
    const sentMessage = page.getByText(messageText);
    await expect(sentMessage).toBeVisible();

    // Input should be cleared after sending
    await expect(messageInput).toHaveValue('');
  });

  test('send message with Enter key', async ({ page }) => {
    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    const messageInput = page.getByPlaceholder('Type a message...');
    const messageText = `Enter key test ${Date.now()}`;
    await messageInput.fill(messageText);

    // Press Enter to send (not Shift+Enter which inserts newline)
    await messageInput.press('Enter');

    const sentMessage = page.getByText(messageText);
    await expect(sentMessage).toBeVisible();
  });

  test('message shows sender name and timestamp', async ({ page }) => {
    const messageText = `Metadata test ${Date.now()}`;
    await sendMessageViaAPI(page, channelId, messageText);

    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    const messageContent = page.getByText(messageText);
    await expect(messageContent).toBeVisible();

    // MessageBubble wraps each message in a .group div
    const messageBubble = page
      .locator('.group')
      .filter({ hasText: messageText });
    await expect(messageBubble).toBeVisible();

    // Sender name is in a span.font-medium inside the .items-baseline div
    const senderName = messageBubble.locator('.items-baseline .font-medium');
    await expect(senderName).toBeVisible();
    await expect(senderName).not.toHaveText('');

    // Timestamp is rendered in a <time> element
    const timestamp = messageBubble.locator('time');
    await expect(timestamp).toBeVisible();
  });

  test('empty channel shows no messages placeholder', async ({ page }) => {
    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    // MessageList.vue shows: "No messages yet. Start the conversation!"
    const emptyText = page.getByText(
      'No messages yet. Start the conversation!'
    );
    await expect(emptyText).toBeVisible();
  });

  test('delete a message removes it from the list', async ({ page }) => {
    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    // Send a message via UI
    const messageText = `Delete me ${Date.now()}`;
    const messageInput = page.getByPlaceholder('Type a message...');
    await messageInput.fill(messageText);
    await messageInput.press('Enter');

    const sentMessage = page.getByText(messageText);
    await expect(sentMessage).toBeVisible();

    // Hover over the message to show action buttons
    const messageBubble = page
      .locator('.group')
      .filter({ hasText: messageText });
    await messageBubble.hover();

    // Click the delete button (title = "Delete" from INTERNAL_CHAT.MESSAGE.DELETE)
    const deleteButton = messageBubble.locator('button[title="Delete"]');
    await expect(deleteButton).toBeVisible();
    await deleteButton.click();

    // After deletion, the message text should be replaced by deleted placeholder
    // INTERNAL_CHAT.MESSAGE.DELETED: "This message was deleted"
    await expect(sentMessage).not.toBeVisible();
    // Don't re-use the original messageBubble locator since it was filtered by
    // the now-removed text. Instead, check the page directly.
    const deletedText = page.getByText('This message was deleted');
    await expect(deletedText).toBeVisible();
  });

  test('edit a message shows edited badge', async ({ page }) => {
    // Send a message via API so we have a known message ID
    const originalText = `Edit me ${Date.now()}`;
    const msg = await sendMessageViaAPI(page, channelId, originalText);

    // Edit the message via API with new content
    const updatedText = `Edited content ${Date.now()}`;
    const baseURL = 'http://localhost:3000';
    await page.request.patch(
      `${baseURL}/api/v1/accounts/${accountId}/internal_chat/channels/${channelId}/messages/${msg.id}`,
      { data: { content: updatedText } }
    );

    // Navigate to the channel and verify
    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    // The updated content should appear
    await expect(page.getByText(updatedText)).toBeVisible();

    // The "(edited)" indicator should be visible
    // MessageBubble shows t('INTERNAL_CHAT.MESSAGE.EDITED') which is "(edited)"
    const messageBubble = page
      .locator('.group')
      .filter({ hasText: updatedText });
    const editedBadge = messageBubble.getByText('(edited)');
    await expect(editedBadge).toBeVisible();
  });

  test('pin a message shows pinned banner in header', async ({ page }) => {
    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    const messageText = `Pin me ${Date.now()}`;
    const messageInput = page.getByPlaceholder('Type a message...');
    await messageInput.fill(messageText);
    await messageInput.press('Enter');

    const sentMessage = page.getByText(messageText);
    await expect(sentMessage).toBeVisible();

    // Hover over the message to show action buttons
    const messageBubble = page
      .locator('.group')
      .filter({ hasText: messageText });
    await messageBubble.hover();

    // Click pin button (title = "Pin message" from INTERNAL_CHAT.PIN.PIN)
    const pinButton = messageBubble.locator('button[title="Pin message"]');
    await expect(pinButton).toBeVisible();
    await pinButton.click();

    // After pinning, the ChannelHeader shows a pinned message banner
    // with text "Pinned message" (INTERNAL_CHAT.PIN.PINNED_MESSAGE)
    const pinnedBanner = page.getByText('Pinned message');
    await expect(pinnedBanner.first()).toBeVisible();
  });

  test('unpin a message removes pinned banner', async ({ page }) => {
    // Send and pin a message via API
    const messageText = `Unpin test ${Date.now()}`;
    const msg = await sendMessageViaAPI(page, channelId, messageText);

    // Pin via API first (using the pin endpoint)
    const accountIdForAPI = accountId;
    await page.request.post(
      `${baseURL}/api/v1/accounts/${accountIdForAPI}/internal_chat/channels/${channelId}/messages/${msg.id}/pin`
    );

    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    // Pinned banner should be visible
    const pinnedBanner = page.getByText('Pinned message');
    await expect(pinnedBanner.first()).toBeVisible();

    // Hover over the pinned message and click unpin
    const messageBubble = page
      .locator('.group')
      .filter({ hasText: messageText });
    await messageBubble.hover();

    // The pin button should now say "Unpin message" (INTERNAL_CHAT.PIN.UNPIN)
    const unpinButton = messageBubble.locator('button[title="Unpin message"]');
    await expect(unpinButton).toBeVisible();
    await unpinButton.click();

    // After unpinning, the banner should disappear
    await expect(pinnedBanner).toHaveCount(0);
  });

  test('date separator appears between messages', async ({ page }) => {
    // Send a message (will have today's date)
    await sendMessageViaAPI(page, channelId, `Date sep test ${Date.now()}`);

    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    // MessageList.vue renders date separators with "Today" text
    const todaySeparator = page.getByText('Today');
    await expect(todaySeparator.first()).toBeVisible();
  });
});
