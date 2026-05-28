import { test, expect } from '@playwright/test';
import {
  login,
  createDMViaAPI,
  sendMessageViaAPI,
  internalChatURL,
  dmURL,
  getOtherAgentId,
} from '../helpers/auth';

test.describe('Internal Chat - Direct Messages', () => {
  const baseURL = 'http://localhost:3000';

  test('create a DM channel via API and see it in sidebar', async ({
    page,
  }) => {
    const { data } = await login(page, baseURL);

    // Create a DM with another user (dynamically find a different agent)
    const targetUserId = await getOtherAgentId(page, data.id);
    const dm = await createDMViaAPI(page, targetUserId);
    expect(dm).toBeTruthy();
    expect(dm.id).toBeTruthy();

    // Navigate to internal chat
    await page.goto(internalChatURL(data.account_id));
    await page.waitForLoadState('networkidle');

    // ChannelSidebar shows DM channels under "Direct Messages" heading
    // (INTERNAL_CHAT.DIRECT_MESSAGES)
    const sidebar = page.locator('.w-64');
    const dmSection = sidebar.locator('h3', { hasText: 'Direct Messages' });
    await expect(dmSection.first()).toBeVisible();
  });

  test('navigate to DM channel and see header with settings', async ({
    page,
  }) => {
    const { data } = await login(page, baseURL);
    const targetUserId = await getOtherAgentId(page, data.id);
    const dm = await createDMViaAPI(page, targetUserId);

    // Navigate to the DM channel
    await page.goto(dmURL(data.account_id, dm.id));
    await page.waitForLoadState('networkidle');

    // ChannelHeader renders with border-b header bar
    // The message-circle icon for DMs is rendered in the header
    const headerBar = page.locator('.border-b.border-n-slate-5.bg-n-solid-2');
    await expect(headerBar.first()).toBeVisible();

    // Settings button should be present in header (aria-label "Channel settings")
    const settingsButton = page.getByRole('button', {
      name: 'Channel settings',
    });
    await expect(settingsButton.first()).toBeVisible();

    // The message editor should be visible (channel is not archived)
    const messageInput = page.getByPlaceholder('Type a message...');
    await expect(messageInput).toBeVisible();
  });

  test('send message in DM channel', async ({ page }) => {
    const { data } = await login(page, baseURL);
    const targetUserId = await getOtherAgentId(page, data.id);
    const dm = await createDMViaAPI(page, targetUserId);

    await page.goto(dmURL(data.account_id, dm.id));
    await page.waitForLoadState('networkidle');

    const messageInput = page.getByPlaceholder('Type a message...');
    await expect(messageInput).toBeVisible();

    const messageText = `DM test message ${Date.now()}`;
    await messageInput.fill(messageText);
    await messageInput.press('Enter');

    // Verify the message appears
    const sentMessage = page.getByText(messageText);
    await expect(sentMessage).toBeVisible();
  });

  test('DM channel shows message-circle icon in sidebar', async ({ page }) => {
    const { data } = await login(page, baseURL);
    const targetUserId = await getOtherAgentId(page, data.id);
    await createDMViaAPI(page, targetUserId);

    await page.goto(internalChatURL(data.account_id));
    await page.waitForLoadState('networkidle');

    // DM channels in ChannelSidebar use i-lucide-message-circle icon
    const sidebar = page.locator('.w-64');
    const dmSection = sidebar.locator('h3', { hasText: 'Direct Messages' });
    await expect(dmSection.first()).toBeVisible();

    // The section header itself has the message-circle icon
    const sectionIcon = dmSection.locator('.i-lucide-message-circle');
    await expect(sectionIcon).toBeVisible();
  });

  test('DM message shows sender name', async ({ page }) => {
    const { data } = await login(page, baseURL);
    const targetUserId = await getOtherAgentId(page, data.id);
    const dm = await createDMViaAPI(page, targetUserId);

    // Send message via API
    const messageText = `DM sender test ${Date.now()}`;
    await sendMessageViaAPI(page, dm.id, messageText);

    await page.goto(dmURL(data.account_id, dm.id));
    await page.waitForLoadState('networkidle');

    const messageBubble = page
      .locator('.group')
      .filter({ hasText: messageText });
    await expect(messageBubble).toBeVisible();

    // Sender name should be visible in the message bubble
    const senderName = messageBubble.locator('.items-baseline .font-medium');
    await expect(senderName).toBeVisible();
    await expect(senderName).not.toHaveText('');
  });
});
