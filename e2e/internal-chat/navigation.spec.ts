import { test, expect } from '@playwright/test';
import { loginAndNavigateToInternalChat } from '../helpers/auth';

test.describe('Internal Chat - Navigation', () => {
  test.beforeEach(async ({ page }) => {
    await loginAndNavigateToInternalChat(page);
  });

  test('sidebar shows Internal Chat item', async ({ page }) => {
    // The sidebar in Sidebar.vue renders a nav item with label from
    // SIDEBAR.INTERNAL_CHAT which resolves to "Internal Chat"
    const sidebarItem = page.getByText('Internal Chat', { exact: true });
    await expect(sidebarItem.first()).toBeVisible();
  });

  test('internal chat layout displays channel sidebar', async ({ page }) => {
    // InternalChatLayout.vue renders ChannelSidebar which has a heading
    // from INTERNAL_CHAT.TITLE = "Internal Chat"
    const sidebarHeading = page.locator('.flex.h-full.w-64 h1, .w-64 h1');
    await expect(sidebarHeading.first()).toBeVisible();
    await expect(sidebarHeading.first()).toHaveText('Internal Chat');
  });

  test('default General channel appears in sidebar', async ({ page }) => {
    // The DefaultChannelSetupService creates a "General" channel
    // Channels are listed as buttons in the sidebar with their name
    const generalChannel = page.getByRole('button', { name: /General/i });
    await expect(generalChannel.first()).toBeVisible();
  });

  test('clicking a channel navigates to channel view', async ({ page }) => {
    // Click on the General channel button in the sidebar
    const generalChannel = page.getByRole('button', { name: /General/i });
    await generalChannel.first().click();

    // ChannelHeader.vue renders an h2 with the channel name
    const channelHeader = page.locator('h2').filter({ hasText: /General/i });
    await expect(channelHeader.first()).toBeVisible();

    // URL should contain /channels/ segment
    await expect(page).toHaveURL(/\/internal-chat\/channels\/\d+/);
  });

  test('search filters channels in sidebar', async ({ page }) => {
    // ChannelSidebar has a search input with placeholder from
    // INTERNAL_CHAT.SEARCH_PLACEHOLDER = "Search channels..."
    const searchInput = page.getByPlaceholder('Search channels...');
    await expect(searchInput).toBeVisible();

    // Type a search query
    await searchInput.fill('General');

    // General channel should still be visible
    const generalChannel = page.getByRole('button', { name: /General/i });
    await expect(generalChannel.first()).toBeVisible();

    // Type a non-matching query
    await searchInput.fill('xyznonexistent');

    // Wait briefly for filter to apply
    await page.waitForTimeout(300);

    // No channel buttons should match (except non-channel buttons like Drafts)
    const channelButtons = page
      .locator('.flex-1.overflow-y-auto')
      .getByRole('button');
    await expect(channelButtons).toHaveCount(0);
  });

  test('Drafts button is visible in sidebar', async ({ page }) => {
    // ChannelSidebar renders a Drafts button with text from
    // INTERNAL_CHAT.DRAFT.TITLE = "Drafts"
    const draftsButton = page.getByRole('button', { name: /Drafts/i });
    await expect(draftsButton).toBeVisible();
  });

  test('empty state shows when no channel is selected', async ({ page }) => {
    // InternalChatLayout shows "No messages yet. Start the conversation!"
    // when no channel is active (INTERNAL_CHAT.CHANNEL.NO_MESSAGES)
    const emptyText = page.getByText(
      'No messages yet. Start the conversation!'
    );
    await expect(emptyText).toBeVisible();
  });
});
