import { test, expect } from '@playwright/test';
import {
  login,
  loginAndNavigateToInternalChat,
  createChannelViaAPI,
} from '../helpers/auth';

test.describe('Internal Chat - Channels', () => {
  test('create a new channel via API and verify it loads when navigated to directly', async ({
    page,
  }) => {
    const baseURL = 'http://localhost:3000';
    const { data } = await login(page, baseURL);

    const channelName = `test-ch-${Date.now()}`;
    const channel = await createChannelViaAPI(page, {
      name: channelName,
      description: 'E2E test channel',
      channel_type: 'public_channel',
    });

    // Navigate directly to the created channel
    await page.goto(
      `${baseURL}/app/accounts/${data.account_id}/internal-chat/channels/${channel.id}`
    );
    await page.waitForLoadState('networkidle');

    // The channel header should show the channel name
    const headerTitle = page.locator('h2').filter({ hasText: channelName });
    await expect(headerTitle).toBeVisible();
  });

  test('navigate to channel and see header with name and description', async ({
    page,
  }) => {
    const baseURL = 'http://localhost:3000';
    const { data } = await login(page, baseURL);

    const channelName = `header-${Date.now()}`;
    const channel = await createChannelViaAPI(page, {
      name: channelName,
      description: 'Channel for header test',
    });

    // Navigate directly to the channel
    await page.goto(
      `${baseURL}/app/accounts/${data.account_id}/internal-chat/channels/${channel.id}`
    );
    await page.waitForLoadState('networkidle');

    // ChannelHeader.vue renders an h2 with channelName
    const headerTitle = page.locator('h2').filter({ hasText: channelName });
    await expect(headerTitle).toBeVisible();

    // Description is shown below the channel name in a <p> tag
    const description = page.getByText('Channel for header test');
    await expect(description).toBeVisible();
  });

  test('clicking General channel shows header and message area', async ({
    page,
  }) => {
    await loginAndNavigateToInternalChat(page);

    // Click General channel in sidebar
    const sidebar = page.locator('.w-64');
    const generalChannel = sidebar.locator('button', {
      hasText: 'General',
    });
    await generalChannel.first().click();

    // ChannelHeader has an h2 with "General"
    const headerTitle = page.locator('h2').filter({ hasText: 'General' });
    await expect(headerTitle).toBeVisible();

    // The message editor textarea should be visible (not archived)
    const messageInput = page.locator('textarea');
    await expect(messageInput.first()).toBeVisible();
  });

  test('settings button is visible in channel header', async ({ page }) => {
    await loginAndNavigateToInternalChat(page);

    // Click General channel
    const sidebar = page.locator('.w-64');
    const generalChannel = sidebar.locator('button', {
      hasText: 'General',
    });
    await generalChannel.first().click();

    // Wait for channel header to load
    const headerTitle = page.locator('h2').filter({ hasText: 'General' });
    await expect(headerTitle).toBeVisible();

    // ChannelHeader has a settings button with i-lucide-settings icon
    const settingsButton = page.locator(
      '.border-b button:has(.i-lucide-settings)'
    );
    await expect(settingsButton.first()).toBeVisible();
  });
});
