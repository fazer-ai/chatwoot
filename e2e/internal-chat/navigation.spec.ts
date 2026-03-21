import { test, expect } from '@playwright/test';
import { loginAndNavigateToInternalChat } from '../helpers/auth';

test.describe('Internal Chat - Navigation', () => {
  test.beforeEach(async ({ page }) => {
    await loginAndNavigateToInternalChat(page);
  });

  test('sidebar shows Chat Interno item and internal chat layout loads', async ({
    page,
  }) => {
    // The main sidebar renders a nav item with label "Chat Interno" (pt_BR)
    // It uses role="button" and the label as title attribute
    const sidebarItem = page.locator('[title="Chat Interno"]');
    await expect(sidebarItem.first()).toBeVisible();

    // The internal chat sidebar panel has an h1 with "Chat Interno"
    const sidebarHeading = page.locator(
      '.w-64 h1, [class*="w-64"] h1'
    );
    await expect(sidebarHeading.first()).toBeVisible();
  });

  test('default General channel appears in sidebar', async ({ page }) => {
    // Channels are listed as buttons inside the sidebar panel (.w-64)
    // Each channel button has a span with the channel name
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

  test('search filters channels in sidebar', async ({ page }) => {
    // ChannelSidebar has a search input with placeholder "Buscar canais..." (pt_BR)
    const searchInput = page.getByPlaceholder('Buscar canais...');
    await expect(searchInput).toBeVisible();

    // Type a search query that matches
    await searchInput.fill('General');

    // General channel should still be visible
    const sidebar = page.locator('.w-64');
    const generalChannel = sidebar.locator('button', {
      hasText: 'General',
    });
    await expect(generalChannel.first()).toBeVisible();

    // Type a non-matching query
    await searchInput.fill('xyznonexistent');

    // Wait for filter to apply
    await page.waitForTimeout(300);

    // The scrollable area should have no channel buttons
    const channelButtons = sidebar
      .locator('.overflow-y-auto')
      .locator('button');
    await expect(channelButtons).toHaveCount(0);
  });

  test('Rascunhos (Drafts) button is visible in sidebar', async ({
    page,
  }) => {
    // ChannelSidebar renders a Drafts button with text "Rascunhos" (pt_BR)
    const sidebar = page.locator('.w-64');
    const draftsButton = sidebar.locator('button', {
      hasText: 'Rascunhos',
    });
    await expect(draftsButton).toBeVisible();
  });

  test('empty state shows when no channel is selected', async ({ page }) => {
    // InternalChatLayout shows empty state text when no channel is active
    // pt_BR: "Nenhuma mensagem ainda. Inicie a conversa!"
    const emptyText = page.getByText(
      'Nenhuma mensagem ainda. Inicie a conversa!'
    );
    await expect(emptyText).toBeVisible();
  });
});
