import { parseRedirectParams } from '../redirectHelpers';

describe('#parseRedirectParams', () => {
  it('returns null when the fragment carries no redirect token', () => {
    expect(parseRedirectParams('')).toBeNull();
    expect(parseRedirectParams('#')).toBeNull();
    expect(parseRedirectParams('#utm_source=x&foo=bar')).toBeNull();
  });

  it('parses the token and the open flag from the fragment', () => {
    expect(parseRedirectParams('#cw_redirect=abc123&cw_open=1')).toEqual({
      token: 'abc123',
      autoOpen: true,
    });
  });

  it('treats a missing cw_open as no auto-open', () => {
    expect(parseRedirectParams('#cw_redirect=abc123')).toEqual({
      token: 'abc123',
      autoOpen: false,
    });
  });
});
