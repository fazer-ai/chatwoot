import { test, expect } from '@playwright/test';
import { login, createChannelViaAPI } from '../helpers/auth';

test.describe('Internal Chat - Polls', () => {
  let channelId: number;
  let accountId: number;
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
    // Create a poll via the polls API (not messages API)
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
    await page.goto(
      `${baseURL}/app/accounts/${accountId}/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // PollDisplay.vue shows the question in an h4
    const pollTitle = page.locator('h4').filter({ hasText: pollQuestion });
    await expect(pollTitle).toBeVisible();

    // The poll options should be visible
    await expect(page.getByText('Option A')).toBeVisible();
    await expect(page.getByText('Option B')).toBeVisible();
    await expect(page.getByText('Option C')).toBeVisible();

    // Vote count shows "0 votos" (pt_BR)
    const voteCount = page.getByText(/0 votos/);
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
    expect(
      createResponse.ok() || createResponse.status() === 201
    ).toBeTruthy();
    const pollData = await createResponse.json();

    // Vote via API (the UI vote doesn't update local store without WebSocket)
    const pollId =
      pollData.content_attributes?.poll?.id || pollData.poll?.id;
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
    await page.goto(
      `${baseURL}/app/accounts/${accountId}/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // The poll should show with the question
    const pollTitle = page.locator('h4').filter({ hasText: pollQuestion });
    await expect(pollTitle).toBeVisible();

    // After voting, the selected option should show a checkmark icon
    const pollCard = page.locator('.rounded-lg.border.border-n-slate-5');
    const checkedIcon = pollCard.locator('.i-lucide-check');
    await expect(checkedIcon.first()).toBeVisible();
  });

  test('poll creator button is accessible from message editor', async ({
    page,
  }) => {
    await page.goto(
      `${baseURL}/app/accounts/${accountId}/internal-chat/channels/${channelId}`
    );
    await page.waitForLoadState('networkidle');

    // MessageEditor has a poll creation button with title "Criar Enquete" (pt_BR)
    const pollButton = page.locator('button[title="Criar Enquete"]');
    await expect(pollButton).toBeVisible();
  });
});
