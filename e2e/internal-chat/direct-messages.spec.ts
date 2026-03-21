import { test, expect } from '@playwright/test';
import {
  login,
  createDMViaAPI,
  sendMessageViaAPI,
} from '../helpers/auth';

test.describe('Internal Chat - Direct Messages', () => {
  test.beforeEach(async ({ page }) => {
    const baseURL = 'http://localhost:3000';
    await login(page, baseURL);
  });

  test('create a DM channel via API and see it in sidebar', async ({
    page,
  }) => {
    // Create a DM with another user (user ID 2 is typically another seeded agent)
    const dm = await createDMViaAPI(page, 2);
    expect(dm).toBeTruthy();
    expect(dm.id).toBeTruthy();

    // Navigate to internal chat
    await page.goto('http://localhost:3000/app/accounts/1/internal-chat');
    await page.waitForLoadState('networkidle');

    // ChannelSidebar shows DM channels under the "Direct Messages" heading
    // (from INTERNAL_CHAT.DIRECT_MESSAGES)
    const dmSection = page.getByText('Direct Messages');
    await expect(dmSection.first()).toBeVisible();
  });

  test('navigate to DM channel and see header', async ({ page }) => {
    const dm = await createDMViaAPI(page, 2);

    // Navigate to the DM channel
    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/dm/${dm.id}`
    );
    await page.waitForLoadState('networkidle');

    // ChannelHeader should show the DM channel name (other user's name)
    const header = page.locator('h2');
    await expect(header.first()).toBeVisible();
  });

  test('send message in DM channel', async ({ page }) => {
    const dm = await createDMViaAPI(page, 2);

    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/dm/${dm.id}`
    );
    await page.waitForLoadState('networkidle');

    // Type and send a message
    const messageInput = page.getByPlaceholder('Type a message...');
    await expect(messageInput).toBeVisible();

    const messageText = `DM test message ${Date.now()}`;
    await messageInput.fill(messageText);
    await messageInput.press('Enter');

    // Verify the message appears
    const sentMessage = page.getByText(messageText);
    await expect(sentMessage).toBeVisible();
  });

  test('DM channel uses message-circle icon in sidebar', async ({ page }) => {
    const dm = await createDMViaAPI(page, 2);

    await page.goto('http://localhost:3000/app/accounts/1/internal-chat');
    await page.waitForLoadState('networkidle');

    // DM channels use the i-lucide-message-circle icon per getChannelIcon()
    // in ChannelSidebar.vue. Verify DMs section exists.
    const dmSection = page.getByText('Direct Messages');
    await expect(dmSection.first()).toBeVisible();

    // The DM channel button should have the message-circle icon
    const dmButtons = page
      .locator('.flex-1.overflow-y-auto')
      .locator('button')
      .filter({ has: page.locator('.i-lucide-message-circle') });
    await expect(dmButtons.first()).toBeVisible();
  });
});
