# Meta Webhook Proxy

## Problem

Some VPS providers silently drop inbound TCP connections from Meta's webhook servers (AS32934) due to overzealous DDoS protection. This causes 15–20% WhatsApp message loss. A reverse proxy on a clean provider (e.g., DigitalOcean) eliminates the drops completely.

```
Meta (WhatsApp) → proxy.example.com (clean provider) → your Chatwoot instance
```

## Architecture

The proxy is a single nginx server that routes requests based on the first path segment:

```
https://proxy.example.com/<upstream_host>/webhooks/whatsapp/%2B<phone>
```

This is the URL you configure in Meta's App Dashboard as the webhook callback URL. The proxy extracts `<upstream_host>`, checks it against an allowlist, and forwards the request to `https://<upstream_host>/webhooks/whatsapp/%2B<phone>`.

### Multi-tenant

One proxy serves multiple Chatwoot instances. Each upstream is identified by its domain in the URL path — no separate config per tenant beyond adding the host to the allowlist.

## Setup

### Prerequisites

- A server (Ubuntu 22.04/24.04) on a provider with clean Meta connectivity (DigitalOcean, AWS, etc.)
- A DNS A record pointing your proxy domain to the server IP (e.g., `proxy.example.com → 1.2.3.4`)
- SSH root access to the server

### 1. Install nginx and certbot

```bash
ssh root@proxy.example.com

apt-get update
apt-get install -y nginx certbot python3-certbot-nginx
```

### 2. Create a temporary HTTP-only config

Certbot needs nginx running to perform the ACME challenge, but the full config references SSL certs that don't exist yet. Start with an HTTP-only config:

```bash
cat > /etc/nginx/sites-available/cw-proxy << 'EOF'
server {
    listen 80;
    server_name proxy.example.com;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 404;
    }
}
EOF
```

Enable the site and reload:

```bash
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/cw-proxy /etc/nginx/sites-enabled/cw-proxy
nginx -t && systemctl reload nginx
```

### 3. Obtain the SSL certificate

```bash
certbot certonly --webroot -w /var/www/html -d proxy.example.com \
  --non-interactive --agree-tos -m your-email@example.com
```

Certbot installs a systemd timer that auto-renews the certificate before it expires.

### 4. Deploy the full proxy config

Replace the temporary config with the full proxy configuration:

```bash
cat > /etc/nginx/sites-available/cw-proxy << 'EOF'
# Allowlist of upstream Chatwoot hosts
# Add new hosts here to enable proxying
map $upstream_host $upstream_allowed {
    default                    0;
    chatwoot.example.com       1;
    # chatwoot.other.com       1;
}

server {
    listen 80;
    server_name proxy.example.com;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name proxy.example.com;

    resolver 1.1.1.1 8.8.8.8 valid=300s;
    resolver_timeout 5s;

    ssl_certificate /etc/letsencrypt/live/proxy.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/proxy.example.com/privkey.pem;

    # Extract upstream host from first path segment, proxy the rest
    location ~ ^/([^/]+)(/.*)$ {
        set $upstream_host $1;
        set $upstream_path $2;

        # Reject hosts not in the allowlist
        if ($upstream_allowed = 0) {
            return 403;
        }

        proxy_pass https://$upstream_host$upstream_path$is_args$args;
        proxy_set_header Host $upstream_host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_ssl_server_name on;
    }

    location / {
        return 404;
    }
}
EOF
```

Test and reload:

```bash
nginx -t && systemctl reload nginx
```

### 5. Verify

```bash
# Root path → 404
curl -s -o /dev/null -w "%{http_code}" https://proxy.example.com/
# Expected: 404

# Unknown host → 403
curl -s -o /dev/null -w "%{http_code}" https://proxy.example.com/unknown.host/webhooks/whatsapp/test
# Expected: 403

# Allowed host → proxied (502 if upstream is unreachable, 200 if live)
curl -s -o /dev/null -w "%{http_code}" https://proxy.example.com/chatwoot.example.com/webhooks/whatsapp/test
# Expected: 502 or 200
```

### 6. Configure Meta webhook URL

In the Meta App Dashboard, set the webhook callback URL to:

```
https://proxy.example.com/<your-chatwoot-domain>/webhooks/whatsapp/%2B<phone>
```

For example, if your Chatwoot is at `chatwoot.example.com` and the phone number is `+5511999999999`:

```
https://proxy.example.com/chatwoot.example.com/webhooks/whatsapp/%2B5511999999999
```

Meta will send both verification (GET) and delivery (POST) requests to this URL. The proxy passes them through transparently.

## Adding a new upstream

1. SSH into the proxy server
2. Edit `/etc/nginx/sites-available/cw-proxy`
3. Add the new host to the `map` block:
   ```nginx
   map $upstream_host $upstream_allowed {
       default                    0;
       chatwoot.example.com       1;
       chatwoot.newclient.com     1;   # ← add this line
   }
   ```
4. Test and reload:
   ```bash
   nginx -t && systemctl reload nginx
   ```
5. Set the Meta webhook callback URL for the new instance to:
   ```
   https://proxy.example.com/chatwoot.newclient.com/webhooks/whatsapp/%2B<phone>
   ```

## Removing an upstream

1. Remove or comment out the host from the `map` block
2. `nginx -t && systemctl reload nginx`
3. Update the Meta webhook callback URL to point directly at the Chatwoot instance (or to a different proxy)

## Key nginx directives

| Directive | Purpose |
|-----------|---------|
| `map $upstream_host $upstream_allowed` | Allowlist of permitted upstream hosts. Only hosts set to `1` are proxied; all others get 403. |
| `proxy_ssl_server_name on` | Enables SNI so the TLS handshake uses the correct hostname for the upstream's certificate. |
| `resolver 1.1.1.1 8.8.8.8 valid=300s` | Required because `proxy_pass` uses a variable (`$upstream_host`), so nginx cannot resolve DNS at config load time. Uses Cloudflare and Google DNS. |
| `proxy_set_header Host $upstream_host` | Sets the Host header to the upstream domain so reverse proxies (Traefik, etc.) route correctly. |

## Failure modes

All recoverable — Meta retries with exponential backoff for up to 36 hours:

| Failure | What happens | Recovery |
|---------|-------------|----------|
| Proxy down | Connection refused | Meta retries |
| Upstream down | 502 Bad Gateway | Meta retries |
| SSL expired | TLS handshake error | Meta retries |

## Important notes

- **Do not rate-limit.** Meta sends webhook deliveries from many IPs in AS32934. Bursts of 10+ requests per second are normal.
- **SSL auto-renewal** is handled by the certbot systemd timer. Verify with `systemctl status certbot.timer`.
- The `%2B` in the URL is the URL-encoded `+` sign for the phone number's country code.
