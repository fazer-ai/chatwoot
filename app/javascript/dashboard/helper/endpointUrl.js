// An admin-configured endpoint that Chatwoot's server calls (an agent bot or a webhook) or that the
// dashboard frames (a dashboard app) can live on a private network: a Docker service name such as
// `http://agents:3000`, or an address like `http://10.40.10.20:3000` that the server reaches through
// SAFE_FETCH_PRIVATE_TARGETS. Vuelidate's `url` rejects both (it requires a public TLD and excludes
// private ranges), so these forms accept any absolute http(s) URL; the URL parser already requires a
// host for both. An empty value passes here, and `required` is what rejects it.
const ENDPOINT_PROTOCOLS = ['http:', 'https:'];

export const endpointUrl = value => {
  if (!value) return true;
  try {
    return ENDPOINT_PROTOCOLS.includes(new URL(value).protocol);
  } catch {
    return false;
  }
};
