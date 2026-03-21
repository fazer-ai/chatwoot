import { test, expect } from '@playwright/test';
import {
  login,
  createChannelViaAPI,
  sendMessageViaAPI,
} from '../helpers/auth';

test.describe('Internal Chat - Messaging', () => {
  let channelId: number;
  let accountId: number;
  const baseURL = 'http://localhost:3000';

  test.beforeEach(async ({ page }) => {
    const { data } = await login(page, baseURL);
    accountId = data.account_id;

    // Create a fresh channel for each test
    const channel = await createChannelViaAPI(page, {
      name: `msg-test-${Date.now()}`,
      description: 'Messaging test channel',
    });
    channelId = channel.id;
  });

  test('send a text message via UI', async ({ page }) => {
    await page.goto(
      `${baseURL}/app/accounts/${accountId}/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // MessageEditor.vue has a <textarea> with placeholder "Digite uma mensagem..." (pt_BR)
    const messageInput = page.locator('textarea');
    await expect(messageInput).toBeVisible();

    const messageText = `Hello E2E ${Date.now()}`;
    await messageInput.fill(messageText);

    // Click the send button (has title "Enviar" in pt_BR)
    const sendButton = page.locator('button[title="Enviar"]');
    await sendButton.click();

    // The message should appear in the message list
    const sentMessage = page.getByText(messageText);
    await expect(sentMessage).toBeVisible();

    // Input should be cleared after sending
    await expect(messageInput).toHaveValue('');
  });

  test('send message with Enter key', async ({ page }) => {
    await page.goto(
      `${baseURL}/app/accounts/${accountId}/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    const messageInput = page.locator('textarea');
    const messageText = `Enter key test ${Date.now()}`;
    await messageInput.fill(messageText);

    // Press Enter to send (not Shift+Enter which is newline)
    await messageInput.press('Enter');

    const sentMessage = page.getByText(messageText);
    await expect(sentMessage).toBeVisible();
  });

  test('message shows sender name and timestamp', async ({ page }) => {
    // Send a message via API as precondition
    const messageText = `Metadata test ${Date.now()}`;
    await sendMessageViaAPI(page, channelId, messageText);

    await page.goto(
      `${baseURL}/app/accounts/${accountId}/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // Wait for the message to appear
    const messageContent = page.getByText(messageText);
    await expect(messageContent).toBeVisible();

    // MessageBubble wraps each message in a .group div
    const messageBubble = page
      .locator('.group')
      .filter({ hasText: messageText });
    await expect(messageBubble).toBeVisible();

    // Sender name is in a span.text-sm.font-medium inside the .items-baseline div
    const senderName = messageBubble.locator(
      '.items-baseline .font-medium'
    );
    await expect(senderName).toBeVisible();
    await expect(senderName).not.toHaveText('');

    // Timestamp in a <time> element
    const timestamp = messageBubble.locator('time');
    await expect(timestamp).toBeVisible();
  });

  test('empty channel shows no messages placeholder', async ({ page }) => {
    await page.goto(
      `${baseURL}/app/accounts/${accountId}/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // MessageList.vue shows empty state: "Nenhuma mensagem ainda. Inicie a conversa!" (pt_BR)
    const emptyText = page.getByText(
      'Nenhuma mensagem ainda. Inicie a conversa!'
    );
    await expect(emptyText).toBeVisible();
  });

  test('delete a message removes it from the list', async ({ page }) => {
    // Navigate to the channel
    await page.goto(
      `${baseURL}/app/accounts/${accountId}/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // Send a message via UI so it's definitely in the channel
    const messageText = `Delete me ${Date.now()}`;
    const messageInput = page.locator('textarea');
    await messageInput.fill(messageText);
    await messageInput.press('Enter');

    // Wait for message to appear
    const sentMessage = page.getByText(messageText);
    await expect(sentMessage).toBeVisible();

    // Hover over the message to show action buttons
    const messageBubble = page
      .locator('.group')
      .filter({ hasText: messageText });
    await messageBubble.hover();

    // Click the delete button (title = "Excluir" in pt_BR)
    const deleteButton = messageBubble.locator('button[title="Excluir"]');
    await expect(deleteButton).toBeVisible();
    await deleteButton.click();

    // After deletion, the Vuex store removes the message from the list
    // so the message text should no longer be visible
    await expect(sentMessage).not.toBeVisible();
  });

  test('pin a message shows pin banner in header', async ({ page }) => {
    // Navigate to channel first, then send message via UI
    await page.goto(
      `${baseURL}/app/accounts/${accountId}/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    const messageText = `Pin me ${Date.now()}`;
    const messageInput = page.locator('textarea');
    await messageInput.fill(messageText);
    await messageInput.press('Enter');

    // Wait for message to appear
    const sentMessage = page.getByText(messageText);
    await expect(sentMessage).toBeVisible();

    // Hover over the message to show action buttons
    const messageBubble = page
      .locator('.group')
      .filter({ hasText: messageText });
    await messageBubble.hover();

    // Click pin button (title = "Fixar mensagem" in pt_BR)
    const pinButton = messageBubble.locator('button[title="Fixar mensagem"]');
    await expect(pinButton).toBeVisible();
    await pinButton.click();

    // After pinning, the ChannelHeader shows a pinned message banner
    // with text "Mensagem fixada" (pt_BR)
    const pinnedBanner = page.getByText('Mensagem fixada');
    await expect(pinnedBanner.first()).toBeVisible();
  });
});
