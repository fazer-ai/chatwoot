import { test, expect } from '@playwright/test';
import {
  login,
  loginAndNavigateToInternalChat,
  createChannelViaAPI,
  archiveChannelViaAPI,
  unarchiveChannelViaAPI,
  channelURL,
} from '../helpers/auth';

test.describe('Internal Chat - Channels', () => {
  const baseURL = 'http://localhost:3000';

  test('create a public channel via API and verify it appears in sidebar', async ({
    page,
  }) => {
    const { data } = await login(page, baseURL);
    const channelName = `pub-ch-${Date.now()}`;

    const channel = await createChannelViaAPI(page, {
      name: channelName,
      description: 'E2E public channel test',
      channel_type: 'public_channel',
    });

    // Navigate to internal chat home
    await page.goto(`${baseURL}/app/accounts/${data.account_id}/internal-chat`);
    await page.waitForLoadState('networkidle');

    // The channel should appear in the sidebar
    const sidebar = page.locator('.w-64');
    const channelButton = sidebar.locator('button', {
      hasText: channelName,
    });
    await expect(channelButton).toBeVisible();

    // Navigate to the channel and verify header
    await page.goto(channelURL(data.account_id, channel.id));
    await page.waitForLoadState('networkidle');

    const headerTitle = page.locator('h2').filter({ hasText: channelName });
    await expect(headerTitle).toBeVisible();
  });

  test('create a private channel via API and verify lock icon in sidebar', async ({
    page,
  }) => {
    const { data } = await login(page, baseURL);
    const channelName = `priv-ch-${Date.now()}`;

    await createChannelViaAPI(page, {
      name: channelName,
      description: 'E2E private channel test',
      channel_type: 'private_channel',
    });

    await page.goto(`${baseURL}/app/accounts/${data.account_id}/internal-chat`);
    await page.waitForLoadState('networkidle');

    // The channel button should be visible in the sidebar
    const sidebar = page.locator('.w-64');
    const channelButton = sidebar.locator('button', {
      hasText: channelName,
    });
    await expect(channelButton).toBeVisible();

    // Private channels use the i-lucide-lock icon (from getChannelIcon)
    const lockIcon = channelButton.locator('.i-lucide-lock');
    await expect(lockIcon).toBeVisible();
  });

  test('navigate to channel and see header with name and description', async ({
    page,
  }) => {
    const { data } = await login(page, baseURL);
    const channelName = `header-${Date.now()}`;

    const channel = await createChannelViaAPI(page, {
      name: channelName,
      description: 'Channel for header test',
    });

    await page.goto(channelURL(data.account_id, channel.id));
    await page.waitForLoadState('networkidle');

    // ChannelHeader.vue renders an h2 with channelName
    const headerTitle = page.locator('h2').filter({ hasText: channelName });
    await expect(headerTitle).toBeVisible();

    // Description is shown below the channel name in a <p> tag
    const description = page.getByText('Channel for header test');
    await expect(description).toBeVisible();
  });

  test('channel header shows settings button', async ({ page }) => {
    await loginAndNavigateToInternalChat(page);

    // Click General channel in sidebar
    const sidebar = page.locator('.w-64');
    const generalChannel = sidebar.locator('button', {
      hasText: 'General',
    });
    await generalChannel.first().click();

    // Wait for channel header to load
    const headerTitle = page.locator('h2').filter({ hasText: 'General' });
    await expect(headerTitle).toBeVisible();

    // ChannelHeader has a settings button with aria-label "Channel settings"
    const settingsButton = page.getByRole('button', {
      name: 'Channel settings',
    });
    await expect(settingsButton).toBeVisible();
  });

  test('channel shows message textarea when not archived', async ({ page }) => {
    await loginAndNavigateToInternalChat(page);

    const sidebar = page.locator('.w-64');
    const generalChannel = sidebar.locator('button', {
      hasText: 'General',
    });
    await generalChannel.first().click();

    const headerTitle = page.locator('h2').filter({ hasText: 'General' });
    await expect(headerTitle).toBeVisible();

    // MessageEditor renders a textarea with placeholder "Type a message..."
    const messageInput = page.getByPlaceholder('Type a message...');
    await expect(messageInput).toBeVisible();
  });

  test('archive channel shows archived banner', async ({ page }) => {
    const { data } = await login(page, baseURL);
    const channelName = `archive-${Date.now()}`;

    const channel = await createChannelViaAPI(page, {
      name: channelName,
    });

    // Navigate to the channel FIRST so it loads into the Vuex store
    await page.goto(channelURL(data.account_id, channel.id));
    await page.waitForLoadState('networkidle');

    // Verify channel loaded before archiving
    const headerTitle = page.locator('h2').filter({ hasText: channelName });
    await expect(headerTitle).toBeVisible();

    // Archive via API while on the page
    await archiveChannelViaAPI(page, channel.id);

    // Reload to reflect archived state
    await page.reload();
    await page.waitForLoadState('networkidle');

    // Archived channels show "This channel is archived" text
    // and the header shows an "Archived" badge
    const archivedText = page.getByText('This channel is archived');
    await expect(archivedText.first()).toBeVisible();

    // The textarea should NOT be visible (replaced by archived message)
    const messageInput = page.getByPlaceholder('Type a message...');
    await expect(messageInput).toHaveCount(0);
  });

  test('unarchive channel restores message editor', async ({ page }) => {
    const { data } = await login(page, baseURL);
    const channelName = `unarchive-${Date.now()}`;

    const channel = await createChannelViaAPI(page, {
      name: channelName,
    });

    // Navigate to the channel FIRST so it loads into the Vuex store
    await page.goto(channelURL(data.account_id, channel.id));
    await page.waitForLoadState('networkidle');

    // Archive then unarchive via API
    await archiveChannelViaAPI(page, channel.id);
    await unarchiveChannelViaAPI(page, channel.id);

    // Reload to reflect unarchived state
    await page.reload();
    await page.waitForLoadState('networkidle');

    // The textarea should be visible again
    const messageInput = page.getByPlaceholder('Type a message...');
    await expect(messageInput).toBeVisible();

    // Archived text should not be visible
    const archivedText = page.getByText('This channel is archived');
    await expect(archivedText).toHaveCount(0);
  });

  test('edit channel name via API and verify update', async ({ page }) => {
    const { data } = await login(page, baseURL);
    const originalName = `edit-orig-${Date.now()}`;

    const channel = await createChannelViaAPI(page, {
      name: originalName,
      description: 'Original description',
    });

    // Update channel via API
    const newName = `edit-updated-${Date.now()}`;
    const newDesc = 'Updated description';
    await page.request.patch(
      `${baseURL}/api/v1/accounts/${data.account_id}/internal_chat/channels/${channel.id}`,
      { data: { channel: { name: newName, description: newDesc } } }
    );

    // Navigate and verify the new name
    await page.goto(channelURL(data.account_id, channel.id));
    await page.waitForLoadState('networkidle');

    const headerTitle = page.locator('h2').filter({ hasText: newName });
    await expect(headerTitle).toBeVisible();

    const description = page.getByText(newDesc);
    await expect(description).toBeVisible();
  });
});
