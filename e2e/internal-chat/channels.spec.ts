import { test, expect } from '@playwright/test';
import {
  login,
  loginAndNavigateToInternalChat,
  createChannelViaAPI,
} from '../helpers/auth';

test.describe('Internal Chat - Channels', () => {
  test.beforeEach(async ({ page }) => {
    const baseURL = 'http://localhost:3000';
    await login(page, baseURL);
  });

  test('create a new public channel via API and see it in sidebar', async ({
    page,
  }) => {
    const channelName = `test-channel-${Date.now()}`;
    const channel = await createChannelViaAPI(page, {
      name: channelName,
      description: 'E2E test channel',
      channel_type: 'public_channel',
    });

    expect(channel).toBeTruthy();

    // Navigate to internal chat to see the new channel in sidebar
    await page.goto('http://localhost:3000/app/accounts/1/internal-chat');
    await page.waitForLoadState('networkidle');

    // The channel name should appear in the sidebar
    const channelButton = page.getByRole('button', { name: channelName });
    await expect(channelButton).toBeVisible();
  });

  test('navigate to created channel and see header', async ({ page }) => {
    const channelName = `header-test-${Date.now()}`;
    const channel = await createChannelViaAPI(page, {
      name: channelName,
      description: 'Channel for header test',
    });

    // Navigate directly to the channel
    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/channels/${channel.id}`
    );
    await page.waitForLoadState('networkidle');

    // ChannelHeader.vue renders an h2 with channelName
    const headerTitle = page.locator('h2').filter({ hasText: channelName });
    await expect(headerTitle).toBeVisible();

    // Description is shown below the channel name
    const description = page.getByText('Channel for header test');
    await expect(description).toBeVisible();
  });

  test('update channel name via API and verify in header', async ({
    page,
  }) => {
    const originalName = `edit-test-${Date.now()}`;
    const channel = await createChannelViaAPI(page, {
      name: originalName,
      description: 'Will be edited',
    });

    const updatedName = `edited-${Date.now()}`;

    // Update the channel via API
    const updateResponse = await page.request.patch(
      `http://localhost:3000/api/v1/accounts/1/internal_chat/channels/${channel.id}`,
      { data: { name: updatedName } }
    );
    expect(updateResponse.ok()).toBeTruthy();

    // Navigate to the channel and verify the updated name
    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/channels/${channel.id}`
    );
    await page.waitForLoadState('networkidle');

    const headerTitle = page.locator('h2').filter({ hasText: updatedName });
    await expect(headerTitle).toBeVisible();
  });

  test('archive a channel shows archived badge', async ({ page }) => {
    const channelName = `archive-test-${Date.now()}`;
    const channel = await createChannelViaAPI(page, {
      name: channelName,
      description: 'Will be archived',
    });

    // Archive the channel via API
    const archiveResponse = await page.request.post(
      `http://localhost:3000/api/v1/accounts/1/internal_chat/channels/${channel.id}/archive`
    );
    expect(archiveResponse.ok()).toBeTruthy();

    // Navigate to the channel
    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/channels/${channel.id}`
    );
    await page.waitForLoadState('networkidle');

    // ChannelHeader.vue shows "This channel is archived" text
    // (from INTERNAL_CHAT.CHANNEL.ARCHIVED)
    const archivedBadge = page.getByText('This channel is archived');
    await expect(archivedBadge.first()).toBeVisible();

    // The MessageEditor should NOT be visible (replaced by archived notice)
    // The archived message bar is shown in ChannelView.vue
    const messageInput = page.getByPlaceholder('Type a message...');
    await expect(messageInput).toHaveCount(0);
  });

  test('settings button is visible in channel header', async ({ page }) => {
    await page.goto('http://localhost:3000/app/accounts/1/internal-chat');
    await page.waitForLoadState('networkidle');

    // Click General channel
    const generalChannel = page.getByRole('button', { name: /General/i });
    await generalChannel.first().click();
    await page.waitForLoadState('networkidle');

    // ChannelHeader has a settings button (icon i-lucide-settings)
    // It's a button in the header area
    const settingsButton = page.locator(
      '.border-b button .i-lucide-settings'
    );
    await expect(settingsButton.first()).toBeVisible();
  });
});
