import { test, expect } from '@playwright/test';
import {
  login,
  createChannelViaAPI,
  sendMessageViaAPI,
} from '../helpers/auth';

test.describe('Internal Chat - Reactions', () => {
  let channelId: number;

  test.beforeEach(async ({ page }) => {
    const baseURL = 'http://localhost:3000';
    await login(page, baseURL);

    const channel = await createChannelViaAPI(page, {
      name: `reaction-test-${Date.now()}`,
    });
    channelId = channel.id;
  });

  test('add emoji reaction to a message', async ({ page }) => {
    // Create a message first
    const messageText = `React to me ${Date.now()}`;
    await sendMessageViaAPI(page, channelId, messageText);

    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // Hover over the message to reveal action buttons
    const messageBubble = page.locator('.group').filter({ hasText: messageText });
    await messageBubble.hover();

    // EmojiReactionPicker toggle button has the i-lucide-smile-plus icon
    const emojiPickerToggle = messageBubble.locator(
      'button:has(.i-lucide-smile-plus)'
    );
    await expect(emojiPickerToggle).toBeVisible();
    await emojiPickerToggle.click();

    // The emoji picker popup shows quick emojis (thumbs up, heart, etc.)
    // Click the thumbs up emoji button (title="thumbs up")
    const thumbsUpButton = page.locator('button[title="thumbs up"]');
    await expect(thumbsUpButton).toBeVisible();
    await thumbsUpButton.click();

    // ReactionDisplay shows the reaction as a button with emoji and count
    // The reaction badge should appear on the message
    const reactionBadge = messageBubble.locator(
      '.inline-flex.items-center.gap-1'
    );
    await expect(reactionBadge.first()).toBeVisible();
  });

  test('remove a reaction by clicking on it', async ({ page }) => {
    const messageText = `Unreact me ${Date.now()}`;
    await sendMessageViaAPI(page, channelId, messageText);

    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // Add a reaction first
    const messageBubble = page.locator('.group').filter({ hasText: messageText });
    await messageBubble.hover();

    const emojiPickerToggle = messageBubble.locator(
      'button:has(.i-lucide-smile-plus)'
    );
    await emojiPickerToggle.click();

    const thumbsUpButton = page.locator('button[title="thumbs up"]');
    await thumbsUpButton.click();

    // Wait for the reaction to appear
    const reactionBadge = messageBubble.locator(
      '.inline-flex.items-center.gap-1'
    );
    await expect(reactionBadge.first()).toBeVisible();

    // Click the reaction badge to remove it (ReactionDisplay handleClick)
    // When the user has reacted, clicking toggles the reaction off
    await reactionBadge.first().click();

    // After removal, the reaction badge should be gone
    await expect(reactionBadge).toHaveCount(0);
  });

  test('emoji picker shows all quick emojis', async ({ page }) => {
    const messageText = `Picker test ${Date.now()}`;
    await sendMessageViaAPI(page, channelId, messageText);

    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    const messageBubble = page.locator('.group').filter({ hasText: messageText });
    await messageBubble.hover();

    const emojiPickerToggle = messageBubble.locator(
      'button:has(.i-lucide-smile-plus)'
    );
    await emojiPickerToggle.click();

    // EmojiReactionPicker.vue defines QUICK_EMOJIS with these titles:
    // thumbs up, heart, joy, surprised, sad, pray, fire, party
    const expectedEmojis = [
      'thumbs up',
      'heart',
      'joy',
      'surprised',
      'sad',
      'pray',
      'fire',
      'party',
    ];

    for (const emojiLabel of expectedEmojis) {
      const emojiButton = page.locator(`button[title="${emojiLabel}"]`);
      await expect(emojiButton).toBeVisible();
    }
  });
});
