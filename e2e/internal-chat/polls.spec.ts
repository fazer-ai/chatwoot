import { test, expect } from '@playwright/test';
import { login, createChannelViaAPI, channelURL } from '../helpers/auth';

test.describe('Internal Chat - Polls', () => {
  let channelId;
  let accountId;
  const baseURL = 'http://localhost:3000';

  test.beforeEach(async ({ page }) => {
    const { data } = await login(page, baseURL);
    accountId = data.account_id;

    const channel = await createChannelViaAPI(page, {
      name: `poll-${Date.now()}`,
    });
    channelId = channel.id;
  });

  test('create a poll via API and see it in channel', async ({ page }) => {
    const pollQuestion = `Poll question ${Date.now()}`;
    const response = await page.request.post(
      `${baseURL}/api/v1/accounts/${accountId}/internal_chat/polls`,
      {
        data: {
          question: pollQuestion,
          channel_id: channelId,
          options: [
            { text: 'Option A' },
            { text: 'Option B' },
            { text: 'Option C' },
          ],
          public_results: true,
        },
      }
    );
    expect(response.ok() || response.status() === 201).toBeTruthy();

    // Navigate to the channel
    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    // PollDisplay.vue shows the question in an h4
    const pollTitle = page.locator('h4').filter({ hasText: pollQuestion });
    await expect(pollTitle).toBeVisible();

    // The poll options should be visible
    await expect(page.getByText('Option A')).toBeVisible();
    await expect(page.getByText('Option B')).toBeVisible();
    await expect(page.getByText('Option C')).toBeVisible();

    // Vote count shows "0 votes" (INTERNAL_CHAT.POLL.VOTES)
    const voteCount = page.getByText(/0 votes/);
    await expect(voteCount).toBeVisible();
  });

  test('vote on a poll option and verify after reload', async ({ page }) => {
    const pollQuestion = `Vote test ${Date.now()}`;
    const createResponse = await page.request.post(
      `${baseURL}/api/v1/accounts/${accountId}/internal_chat/polls`,
      {
        data: {
          question: pollQuestion,
          channel_id: channelId,
          options: [{ text: 'Yes' }, { text: 'No' }],
          public_results: true,
        },
      }
    );
    expect(createResponse.ok() || createResponse.status() === 201).toBeTruthy();
    const pollData = await createResponse.json();

    // Vote via API (the UI vote may not update local store without WebSocket)
    const pollId = pollData.content_attributes?.poll?.id || pollData.poll?.id;
    const optionId =
      pollData.content_attributes?.poll?.options?.[0]?.id ||
      pollData.poll?.options?.[0]?.id;

    if (pollId && optionId) {
      const voteResponse = await page.request.post(
        `${baseURL}/api/v1/accounts/${accountId}/internal_chat/polls/${pollId}/vote`,
        { data: { option_id: optionId } }
      );
      expect(voteResponse.ok()).toBeTruthy();
    }

    // Navigate to the channel to see the poll with the vote
    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    // The poll should show with the question
    const pollTitle = page.locator('h4').filter({ hasText: pollQuestion });
    await expect(pollTitle).toBeVisible();

    // After voting, the selected option should show a checkmark icon
    // PollDisplay: voted options have i-lucide-check inside a bg-n-brand circle
    const pollCard = page.locator('.rounded-lg.border.border-n-slate-5');
    const checkedIcon = pollCard.locator('.i-lucide-check');
    await expect(checkedIcon.first()).toBeVisible();
  });

  test('poll creator button is accessible from message editor', async ({
    page,
  }) => {
    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    // MessageEditor has a poll creation button with title "Create Poll"
    // (INTERNAL_CHAT.POLL.CREATE)
    const pollButton = page.locator('button[title="Create Poll"]');
    await expect(pollButton).toBeVisible();
  });

  test('poll creator dialog opens and has required fields', async ({
    page,
  }) => {
    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    // Click the poll creation button
    const pollButton = page.locator('button[title="Create Poll"]');
    await pollButton.click();

    // PollCreator dialog should open with title "Create Poll"
    const dialogTitle = page.locator('h3').filter({ hasText: 'Create Poll' });
    await expect(dialogTitle).toBeVisible();

    // Should have question input with placeholder "Question"
    const questionInput = page.getByPlaceholder('Question');
    await expect(questionInput).toBeVisible();

    // Should have at least two option inputs
    const optionInputs = page.getByPlaceholder(/^Option \d+$/);
    const count = await optionInputs.count();
    expect(count).toBeGreaterThanOrEqual(2);

    // Should have "Add option" button
    const addOptionButton = page.getByText('Add option');
    await expect(addOptionButton).toBeVisible();

    // Should have "Multiple choice" toggle label
    const multipleChoiceLabel = page.getByText('Multiple choice');
    await expect(multipleChoiceLabel).toBeVisible();

    // Should have Cancel and Create Poll buttons
    const cancelButton = page.getByText('Cancel');
    await expect(cancelButton).toBeVisible();

    // The submit button should be disabled when no question is entered
    const submitButton = page
      .locator('button')
      .filter({ hasText: 'Create Poll' })
      .last();
    await expect(submitButton).toBeDisabled();
  });

  test('poll creator close button dismisses dialog', async ({ page }) => {
    await page.goto(channelURL(accountId, channelId));
    await page.waitForLoadState('networkidle');

    const pollButton = page.locator('button[title="Create Poll"]');
    await pollButton.click();

    // Dialog should be visible
    const dialogTitle = page.locator('h3').filter({ hasText: 'Create Poll' });
    await expect(dialogTitle).toBeVisible();

    // Click cancel
    const cancelButton = page.locator('button').filter({ hasText: 'Cancel' });
    await cancelButton.click();

    // Dialog should close
    await expect(dialogTitle).toHaveCount(0);
  });
});
