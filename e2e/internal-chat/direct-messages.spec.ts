import { test, expect } from '@playwright/test';
import { login, createDMViaAPI } from '../helpers/auth';

test.describe('Internal Chat - Direct Messages', () => {
  const baseURL = 'http://localhost:3000';

  test('create a DM channel via API and see it in sidebar', async ({
    page,
  }) => {
    const { data } = await login(page, baseURL);

    // Create a DM with another user (user ID 2 is typically another seeded agent)
    const dm = await createDMViaAPI(page, 2);
    expect(dm).toBeTruthy();
    expect(dm.id).toBeTruthy();

    // Navigate to internal chat
    await page.goto(
      `${baseURL}/app/accounts/${data.account_id}/internal-chat`
    );
    await page.waitForLoadState('networkidle');

    // ChannelSidebar shows DM channels under "Mensagens Diretas" heading (pt_BR)
    const sidebar = page.locator('.w-64');
    const dmSection = sidebar.getByText('Mensagens Diretas');
    await expect(dmSection.first()).toBeVisible();
  });

  test('navigate to DM channel and see channel header with settings', async ({
    page,
  }) => {
    const { data } = await login(page, baseURL);
    const dm = await createDMViaAPI(page, 2);

    // Navigate to the DM channel
    await page.goto(
      `${baseURL}/app/accounts/${data.account_id}/internal-chat/dm/${dm.id}`
    );
    await page.waitForLoadState('networkidle');

    // ChannelHeader renders with a border-b header bar containing the icon and settings button
    // The message-circle icon for DMs is rendered in the header
    const headerBar = page.locator('.border-b.border-n-slate-5.bg-n-solid-2');
    await expect(headerBar.first()).toBeVisible();

    // Settings button should be present in header
    const settingsButton = headerBar.locator('button:has(.i-lucide-settings)');
    await expect(settingsButton.first()).toBeVisible();

    // The message editor should be visible (channel is not archived)
    const messageInput = page.locator('textarea');
    await expect(messageInput).toBeVisible();
  });

  test('send message in DM channel', async ({ page }) => {
    const { data } = await login(page, baseURL);
    const dm = await createDMViaAPI(page, 2);

    await page.goto(
      `${baseURL}/app/accounts/${data.account_id}/internal-chat/dm/${dm.id}`
    );
    await page.waitForLoadState('networkidle');

    // Type and send a message using the textarea
    const messageInput = page.locator('textarea');
    await expect(messageInput).toBeVisible();

    const messageText = `DM test message ${Date.now()}`;
    await messageInput.fill(messageText);
    await messageInput.press('Enter');

    // Verify the message appears
    const sentMessage = page.getByText(messageText);
    await expect(sentMessage).toBeVisible();
  });
});
