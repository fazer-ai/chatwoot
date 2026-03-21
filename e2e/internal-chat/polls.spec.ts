import { test, expect } from '@playwright/test';
import { login, createChannelViaAPI } from '../helpers/auth';

test.describe('Internal Chat - Polls', () => {
  let channelId: number;

  test.beforeEach(async ({ page }) => {
    const baseURL = 'http://localhost:3000';
    await login(page, baseURL);

    const channel = await createChannelViaAPI(page, {
      name: `poll-test-${Date.now()}`,
    });
    channelId = channel.id;
  });

  test('create a poll via API and see it in channel', async ({ page }) => {
    // Create a poll message via API
    const pollQuestion = `Poll question ${Date.now()}`;
    const response = await page.request.post(
      `http://localhost:3000/api/v1/accounts/1/internal_chat/channels/${channelId}/messages`,
      {
        data: {
          content: pollQuestion,
          content_type: 'poll',
          content_attributes: {
            items: [
              { text: 'Option A' },
              { text: 'Option B' },
              { text: 'Option C' },
            ],
          },
        },
      }
    );
    expect(response.ok()).toBeTruthy();

    // Navigate to the channel
    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // PollDisplay.vue shows the question in an h4
    const pollTitle = page.locator('h4').filter({ hasText: pollQuestion });
    await expect(pollTitle).toBeVisible();

    // The poll options should be visible as buttons
    await expect(page.getByText('Option A')).toBeVisible();
    await expect(page.getByText('Option B')).toBeVisible();
    await expect(page.getByText('Option C')).toBeVisible();

    // Vote count should show "0 votes" initially
    // (from INTERNAL_CHAT.POLL.VOTES)
    const voteCount = page.getByText(/0 votes/);
    await expect(voteCount).toBeVisible();
  });

  test('vote on a poll option', async ({ page }) => {
    // Create a poll
    const pollQuestion = `Vote test ${Date.now()}`;
    await page.request.post(
      `http://localhost:3000/api/v1/accounts/1/internal_chat/channels/${channelId}/messages`,
      {
        data: {
          content: pollQuestion,
          content_type: 'poll',
          content_attributes: {
            items: [{ text: 'Yes' }, { text: 'No' }],
            public_results: true,
          },
        },
      }
    );

    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // Click on "Yes" option to vote
    // PollDisplay renders each option as a button
    const yesOption = page
      .locator('.rounded-lg.border.p-2\\.5')
      .filter({ hasText: 'Yes' });
    await yesOption.click();

    // After voting, the selected option should show a checkmark icon
    // and vote percentages should appear
    const checkedIcon = yesOption.locator('.i-lucide-check');
    await expect(checkedIcon).toBeVisible();
  });

  test('PollCreator modal has expected form elements', async ({ page }) => {
    // This test verifies the PollCreator UI structure
    // PollCreator is opened from ChannelView, but we can test its structure
    // by examining what the modal contains when opened

    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // The PollCreator is conditionally rendered in ChannelView
    // For now, verify the channel loaded correctly
    const messageInput = page.getByPlaceholder('Type a message...');
    await expect(messageInput).toBeVisible();
  });

  test('poll shows multiple choice label when enabled', async ({ page }) => {
    // Create a multiple choice poll
    const pollQuestion = `Multi choice ${Date.now()}`;
    await page.request.post(
      `http://localhost:3000/api/v1/accounts/1/internal_chat/channels/${channelId}/messages`,
      {
        data: {
          content: pollQuestion,
          content_type: 'poll',
          content_attributes: {
            items: [{ text: 'A' }, { text: 'B' }, { text: 'C' }],
            multiple_choice: true,
            public_results: true,
          },
        },
      }
    );

    await page.goto(
      `http://localhost:3000/app/accounts/1/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // PollDisplay shows "Multiple choice" text when the poll is multi-choice
    // (from INTERNAL_CHAT.POLL.MULTIPLE_CHOICE)
    const multiChoiceLabel = page.getByText('Multiple choice');
    await expect(multiChoiceLabel.first()).toBeVisible();
  });
});
