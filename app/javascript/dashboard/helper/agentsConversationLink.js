// An inbox whose agent bot delivers to fazer.ai agents has an outgoing URL ending in this path plus a
// route token. The link is built from what comes before the path, so the token never leaves here.
const AGENTS_WEBHOOK_PATH = '/api/v1/chatwoot/webhook/';

export const agentsConversationUrl = (
  outgoingUrl,
  { accountId, conversationId, inboxId }
) => {
  if (!outgoingUrl) return null;
  let url;
  try {
    url = new URL(outgoingUrl);
  } catch {
    return null;
  }
  const at = url.pathname.indexOf(AGENTS_WEBHOOK_PATH);
  if (at === -1) return null;
  const base = `${url.origin}${url.pathname.slice(0, at)}`;
  return `${base}/chatwoot/accounts/${accountId}/conversations/${conversationId}?inbox=${inboxId}`;
};
