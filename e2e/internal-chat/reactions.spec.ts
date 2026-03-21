import { test, expect } from '@playwright/test';
import {
  login,
  createChannelViaAPI,
  sendMessageViaAPI,
} from '../helpers/auth';

test.describe('Internal Chat - Reactions', () => {
  let channelId: number;
  let accountId: number;
  const baseURL = 'http://localhost:3000';

  test.beforeEach(async ({ page }) => {
    const { data } = await login(page, baseURL);
    accountId = data.account_id;

    const channel = await createChannelViaAPI(page, {
      name: `reaction-${Date.now()}`,
    });
    channelId = channel.id;
  });

  test('add emoji reaction to a message via hover menu', async ({ page }) => {
    // Create a message via API as precondition
    const messageText = `React to me ${Date.now()}`;
    await sendMessageViaAPI(page, channelId, messageText);

    await page.goto(
      `${baseURL}/app/accounts/${accountId}/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // Wait for the message to appear
    await expect(page.getByText(messageText)).toBeVisible();

    // Hover over the message to reveal action buttons
    const messageBubble = page
      .locator('.group')
      .filter({ hasText: messageText });
    await messageBubble.hover();

    // EmojiReactionPicker toggle button has the i-lucide-smile-plus icon
    const emojiPickerToggle = messageBubble.locator(
      'button:has(.i-lucide-smile-plus)'
    );
    await expect(emojiPickerToggle).toBeVisible();
    await emojiPickerToggle.click();

    // The emoji picker popup shows quick emojis with title attributes
    // Click the thumbs up emoji button
    const thumbsUpButton = page.locator('button[title="thumbs up"]');
    await expect(thumbsUpButton).toBeVisible();
    await thumbsUpButton.click();

    // ReactionDisplay renders reaction badges as inline-flex buttons
    const reactionBadge = messageBubble.locator(
      'button.inline-flex.items-center'
    );
    await expect(reactionBadge.first()).toBeVisible();
  });

  test('emoji picker shows all quick emojis', async ({ page }) => {
    const messageText = `Picker test ${Date.now()}`;
    await sendMessageViaAPI(page, channelId, messageText);

    await page.goto(
      `${baseURL}/app/accounts/${accountId}/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    await expect(page.getByText(messageText)).toBeVisible();

    const messageBubble = page
      .locator('.group')
      .filter({ hasText: messageText });
    await messageBubble.hover();

    const emojiPickerToggle = messageBubble.locator(
      'button:has(.i-lucide-smile-plus)'
    );
    await emojiPickerToggle.click();

    // EmojiReactionPicker.vue defines QUICK_EMOJIS with these title attributes
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
