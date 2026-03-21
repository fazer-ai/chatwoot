import { Page } from '@playwright/test';

const DEFAULT_EMAIL = 'john@acme.inc';
const DEFAULT_PASSWORD = 'Password1!';

export async function login(
  page: Page,
  baseURL: string,
  email = DEFAULT_EMAIL,
  password = DEFAULT_PASSWORD
) {
  const response = await page.request.post(`${baseURL}/auth/sign_in`, {
    data: { email, password },
  });

  if (!response.ok()) {
    throw new Error(`Login failed with status ${response.status()}`);
  }

  const body = await response.json();
  const data = body.data;

  const authData = JSON.stringify({
    user_id: data.id,
    name: data.name,
    avatar_url: data.avatar_url,
    access_token: data.access_token || response.headers()['access-token'],
    account_id: data.account_id,
  });

  await page.context().addCookies([
    {
      name: 'cw_d_session_info',
      value: encodeURIComponent(authData),
      domain: 'localhost',
      path: '/',
    },
  ]);

  const headers = response.headers();
  await page.context().setExtraHTTPHeaders({
    'access-token': headers['access-token'] || '',
    'token-type': headers['token-type'] || 'Bearer',
    client: headers['client'] || '',
    uid: headers['uid'] || '',
  });

  return { data, headers };
}

export async function loginAndNavigateToInternalChat(page: Page) {
  const baseURL = 'http://localhost:3000';
  const { data } = await login(page, baseURL);
  await page.goto(
    `${baseURL}/app/accounts/${data.account_id}/internal-chat`
  );
  await page.waitForLoadState('networkidle');
}

export async function loginAndNavigateToChannel(
  page: Page,
  channelId: number
) {
  const baseURL = 'http://localhost:3000';
  const { data } = await login(page, baseURL);
  await page.goto(
    `${baseURL}/app/accounts/${data.account_id}/internal-chat/channels/${channelId}`
  );
  await page.waitForLoadState('networkidle');
}

async function getAccountId(page: Page): Promise<number> {
  const cookies = await page.context().cookies();
  const sessionCookie = cookies.find(c => c.name === 'cw_d_session_info');
  if (sessionCookie) {
    const parsed = JSON.parse(decodeURIComponent(sessionCookie.value));
    return parsed.account_id;
  }
  throw new Error('No session cookie found — call login() first');
}

export async function createChannelViaAPI(
  page: Page,
  channelData: { name: string; description?: string; channel_type?: string }
) {
  const baseURL = 'http://localhost:3000';
  const accountId = await getAccountId(page);
  const response = await page.request.post(
    `${baseURL}/api/v1/accounts/${accountId}/internal_chat/channels`,
    { data: { channel: channelData } }
  );
  return response.json();
}

export async function createDMViaAPI(page: Page, targetUserId: number) {
  const baseURL = 'http://localhost:3000';
  const accountId = await getAccountId(page);
  const response = await page.request.post(
    `${baseURL}/api/v1/accounts/${accountId}/internal_chat/channels`,
    {
      data: {
        channel: {
          channel_type: 'dm',
          member_ids: [targetUserId],
        },
      },
    }
  );
  return response.json();
}

export async function sendMessageViaAPI(
  page: Page,
  channelId: number,
  content: string
) {
  const baseURL = 'http://localhost:3000';
  const accountId = await getAccountId(page);
  const response = await page.request.post(
    `${baseURL}/api/v1/accounts/${accountId}/internal_chat/channels/${channelId}/messages`,
    { data: { content } }
  );
  return response.json();
}
