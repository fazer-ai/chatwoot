import { test, expect } from '@playwright/test';
import {
  login,
  createChannelViaAPI,
  sendMessageViaAPI,
  addReactionViaAPI,
  channelURL,
} from '../helpers/auth';

test.describe('Internal Chat - Reactions', () => {
  let channelId;
  let accountId;
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
    const messageText = `React to me ${Date.now()}`;
    await sendMessageViaAPI(page, channelId, messageText);

    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

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

    await page.goto(channelURL(accountId, channelId));
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

    await Promise.all(
      expectedEmojis.map(emojiLabel =>
        expect(page.locator(`button[title="${emojiLabel}"]`)).toBeVisible()
      )
    );
  });

  test('reaction badge shows count', async ({ page }) => {
    const messageText = `Reaction count ${Date.now()}`;
    const msg = await sendMessageViaAPI(page, channelId, messageText);

    // Add a reaction via API
    await addReactionViaAPI(page, msg.id, '\uD83D\uDC4D');

    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    await expect(page.getByText(messageText)).toBeVisible();

    const messageBubble = page
      .locator('.group')
      .filter({ hasText: messageText });

    // ReactionDisplay shows grouped reactions with emoji + count
    const reactionBadge = messageBubble.locator(
      'button.inline-flex.items-center'
    );
    await expect(reactionBadge.first()).toBeVisible();

    // The badge should contain the count "1"
    await expect(reactionBadge.first()).toContainText('1');
  });

  test('clicking own reaction badge removes it', async ({ page }) => {
    const messageText = `Remove reaction ${Date.now()}`;
    const msg = await sendMessageViaAPI(page, channelId, messageText);

    // Add a reaction via API
    await addReactionViaAPI(page, msg.id, '\uD83D\uDC4D');

    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    await expect(page.getByText(messageText)).toBeVisible();

    const messageBubble = page
      .locator('.group')
      .filter({ hasText: messageText });

    // The reaction badge should be visible with the user's reaction highlighted
    // (border-n-brand class when it's the current user's reaction)
    const reactionBadge = messageBubble.locator(
      'button.inline-flex.items-center'
    );
    await expect(reactionBadge.first()).toBeVisible();

    // Click the badge to remove the reaction
    await reactionBadge.first().click();

    // After removal, the reaction badge should disappear
    await expect(reactionBadge).toHaveCount(0);
  });
});
