import { agentsConversationUrl } from '../agentsConversationLink';

const ref = { accountId: 3, conversationId: 42, inboxId: 9 };

describe('agentsConversationUrl', () => {
  it('links to the conversation page of the agents install the bot delivers to, without the route token', () => {
    const url = agentsConversationUrl(
      'https://agents.example.com/api/v1/chatwoot/webhook/secret-token',
      ref
    );
    expect(url).toBe(
      'https://agents.example.com/chatwoot/accounts/3/conversations/42?inbox=9'
    );
    expect(url).not.toContain('secret-token');
  });

  it('keeps a path prefix the install is served under', () => {
    expect(
      agentsConversationUrl(
        'https://example.com/agents/api/v1/chatwoot/webhook/t',
        ref
      )
    ).toBe(
      'https://example.com/agents/chatwoot/accounts/3/conversations/42?inbox=9'
    );
  });

  it('gives nothing for a bot that is not fazer.ai agents, an empty URL or one that does not parse', () => {
    expect(
      agentsConversationUrl('https://bot.example.com/webhook', ref)
    ).toBeNull();
    expect(agentsConversationUrl('', ref)).toBeNull();
    expect(agentsConversationUrl(undefined, ref)).toBeNull();
    expect(
      agentsConversationUrl('not a url /api/v1/chatwoot/webhook/t', ref)
    ).toBeNull();
  });
});
