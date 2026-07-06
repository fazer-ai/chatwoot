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
