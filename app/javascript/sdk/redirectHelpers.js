export const parseRedirectParams = hash => {
  const params = new URLSearchParams((hash || '').replace(/^#/, ''));
  const token = params.get('cw_redirect');
  if (!token) {
    return null;
  }
  return {
    token,
    autoOpen: params.get('cw_open') === '1',
  };
};

// Strip only the redirect-specific params from the fragment, preserving any
// other hash state the host page may rely on.
export const stripRedirectParams = hash => {
  const params = new URLSearchParams((hash || '').replace(/^#/, ''));
  params.delete('cw_redirect');
  params.delete('cw_open');
  const remaining = params.toString();
  return remaining ? `#${remaining}` : '';
};
