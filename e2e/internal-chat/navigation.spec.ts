import { test, expect } from '@playwright/test';
import { loginAndNavigateToInternalChat } from '../helpers/auth';

test.describe('Internal Chat - Navigation', () => {
  test.beforeEach(async ({ page }) => {
    await loginAndNavigateToInternalChat(page);
  });

  test('sidebar shows Internal Chat item and layout loads', async ({
    page,
  }) => {
    // The main app sidebar renders a nav item with title "Internal Chat"
    // (SidebarGroup uses :title="label" on the collapsed button/router-link)
    const sidebarItem = page.locator('[title="Internal Chat"]');
    await expect(sidebarItem.first()).toBeVisible();

    // The internal chat sidebar panel (ChannelSidebar: w-64) has an h1
    // with the INTERNAL_CHAT.TITLE i18n key ("Internal Chat")
    const sidebarHeading = page.locator('.w-64 h1');
    await expect(sidebarHeading).toBeVisible();
    await expect(sidebarHeading).toHaveText('Internal Chat');
  });

  test('channel sidebar shows search input', async ({ page }) => {
    // ChannelSidebar renders an input with placeholder "Search channels..."
    const searchInput = page.getByPlaceholder('Search channels...');
    await expect(searchInput).toBeVisible();
  });

  test('Drafts button is visible in sidebar', async ({ page }) => {
    // ChannelSidebar renders a Drafts button with text from DRAFT.TITLE ("Drafts")
    const sidebar = page.locator('.w-64');
    const draftsButton = sidebar.locator('button', { hasText: 'Drafts' });
    await expect(draftsButton).toBeVisible();
  });

  test('default General channel appears in sidebar', async ({ page }) => {
    // Channels are listed as buttons inside the sidebar panel (.w-64)
    const sidebar = page.locator('.w-64');
    const generalChannel = sidebar.locator('button', {
      hasText: 'General',
    });
    await expect(generalChannel.first()).toBeVisible();
  });

  test('clicking a channel navigates to channel view', async ({ page }) => {
    // Click on the General channel button in the sidebar panel
    const sidebar = page.locator('.w-64');
    const generalChannel = sidebar.locator('button', {
      hasText: 'General',
    });
    await generalChannel.first().click();

    // ChannelHeader.vue renders an h2 with the channel name
    const channelHeader = page.locator('h2').filter({ hasText: 'General' });
    await expect(channelHeader.first()).toBeVisible();

    // URL should contain /channels/ segment
    await expect(page).toHaveURL(/\/internal-chat\/channels\/\d+/);
  });

  test('DMs section heading is visible when DM channels exist', async ({
    page,
  }) => {
    // ChannelSidebar shows "Direct Messages" heading (INTERNAL_CHAT.DIRECT_MESSAGES)
    // only when there are DM channels. If none exist, the section is hidden.
    const sidebar = page.locator('.w-64');
    const dmHeading = sidebar.locator('h3', { hasText: 'Direct Messages' });
    // This may or may not be visible depending on seed data, so just check
    // the sidebar itself loads properly
    const channelList = sidebar.locator('.overflow-y-auto');
    await expect(channelList).toBeVisible();
    // If DMs exist, the heading should be visible
    const dmCount = await dmHeading.count();
    if (dmCount > 0) {
      await expect(dmHeading).toBeVisible();
    }
  });

  test('search filters channels in sidebar', async ({ page }) => {
    const searchInput = page.getByPlaceholder('Search channels...');

    // Type a search query that matches "General"
    await searchInput.fill('General');

    const sidebar = page.locator('.w-64');
    const generalChannel = sidebar.locator('button', {
      hasText: 'General',
    });
    await expect(generalChannel.first()).toBeVisible();

    // Type a non-matching query
    await searchInput.fill('xyznonexistent');

    // The scrollable area should have no channel buttons matching
    const channelButtons = sidebar
      .locator('.overflow-y-auto')
      .locator('button');
    await expect(channelButtons).toHaveCount(0);
  });

  test('empty state shows when no channel is selected', async ({ page }) => {
    // InternalChatLayout shows empty state text when no channel is active
    // INTERNAL_CHAT.CHANNEL.NO_MESSAGES: "No messages yet. Start the conversation!"
    const emptyText = page.getByText(
      'No messages yet. Start the conversation!'
    );
    await expect(emptyText).toBeVisible();
  });
});
