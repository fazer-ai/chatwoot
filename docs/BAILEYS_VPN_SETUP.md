# VPN Setup for Baileys API (Gluetun + Mullvad)

## Problem

Hosting providers like Hostinger have their IP ranges mass-blocked by Meta. This causes WhatsApp connections through Baileys to fail. The solution is to route **only** Baileys traffic through a VPN, keeping everything else (Rails, Sidekiq, Postgres, Redis) on the regular network.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Docker Network (coolify)                           │
│                                                     │
│  ┌──────────┐    ┌──────────────────────────────┐   │
│  │  Rails    │    │  Gluetun (VPN tunnel)        │   │
│  │  Sidekiq  │───▶│  :3025 ──▶ Baileys API      │   │
│  └──────────┘    │  (network_mode: service)     │   │
│       │          │         │                     │   │
│       │          │         │ VPN (WireGuard)     │   │
│       │          │         ▼                     │   │
│       │          │    Mullvad SP (Brazil)        │   │
│       │          └──────────────────────────────┘   │
│       │                    │                        │
│       ▼                    ▼                        │
│  ┌──────────┐        ┌──────────┐                   │
│  │  Redis   │◀───────│ Baileys  │                   │
│  │  Postgres│        │ (via VPN)│                   │
│  └──────────┘        └──────────┘                   │
└─────────────────────────────────────────────────────┘
```

**Gluetun** creates a WireGuard VPN tunnel. Baileys shares Gluetun's network via `network_mode: "service:gluetun"`, so all WhatsApp traffic exits through the VPN IP. Internal Docker traffic (Redis, etc.) is exempted via firewall subnet rules.

---

## Step 1 — Get Mullvad Credentials

1. Go to <https://mullvad.net/en/account/create> and generate an account (no email needed — save the 16-digit account number).
2. Add credit (€5/month, accepts card, PayPal, crypto).
3. Go to <https://mullvad.net/en/account/wireguard-config>, log in, select **Linux**, click **Generate key**, choose **Brazil > São Paulo**, and download the `.conf` file.
4. From the downloaded file, note:
   - `PrivateKey` — e.g. `KLaIt4oAaI6Iz4iQhSS9/0UBlbvfmG1LC/NWGXW/DH4=`
   - `Address` — use **only the IPv4** address, e.g. `10.67.152.85/32` (discard the IPv6 address)

> **Important:** Gluetun does not support IPv6. Only use the IPv4 address from the `.conf` file.

---

## Step 2 — Docker Compose Changes

### 2.1 Add the `gluetun` service (baileys-api compose)

```yaml
gluetun:
  image: qmcgaw/gluetun
  restart: always
  cap_add:
    - NET_ADMIN
  ports:
    - '3025:3025'
  environment:
    - VPN_SERVICE_PROVIDER=mullvad
    - VPN_TYPE=wireguard
    - WIREGUARD_PRIVATE_KEY=<your-private-key>
    - WIREGUARD_ADDRESSES=<your-ipv4-address>/32
    - SERVER_COUNTRIES=Brazil
    - SERVER_CITIES=Sao Paulo
    - FIREWALL_OUTBOUND_SUBNETS=172.16.0.0/12,10.0.0.0/8,192.168.0.0/16
    - DNS_KEEP_NAMESERVER=on
  healthcheck:
    test:
      - CMD-SHELL
      - 'wget -qO- https://ipinfo.io/ip'
    interval: 30s
    timeout: 10s
    retries: 5
  networks:
    - coolify
```

Key environment variables:

| Variable | Purpose |
|---|---|
| `FIREWALL_OUTBOUND_SUBNETS` | Allows internal Docker traffic (Redis, etc.) to bypass the VPN. Must cover all private subnets used by Docker. |
| `DNS_KEEP_NAMESERVER` | Keeps Docker's internal DNS so containers can resolve hostnames like `redis`. Without this, you get `getaddrinfo ENOTFOUND` errors. |

> **Do NOT set `OWNED_ONLY=yes`** — Mullvad does not have owned servers in São Paulo, only rented ones. This filter would match zero servers.

### 2.2 Modify the `baileys-api` service

Apply these changes to the existing baileys-api service:

```yaml
baileys-api:
  # ... existing config ...
  network_mode: 'service:gluetun'       # Route all traffic through Gluetun
  depends_on:
    gluetun:
      condition: service_healthy         # Wait for VPN to be up
  # REMOVE any 'ports' section — port 3025 is now exposed by gluetun
  # REMOVE any 'networks' section — network_mode is incompatible with networks
```

> **`condition: service_healthy`** is critical. Without it, baileys-api starts before the VPN tunnel is established, causing Redis connection timeouts.

### 2.3 Update `BAILEYS_PROVIDER_DEFAULT_URL` in Chatwoot

In the Rails and Sidekiq services (or Coolify environment variables), change:

```
# Before
BAILEYS_PROVIDER_DEFAULT_URL=http://baileys-api:3025

# After
BAILEYS_PROVIDER_DEFAULT_URL=http://gluetun:3025
```

Since baileys-api now shares Gluetun's network, external services must address it via `gluetun` hostname.

### 2.4 Declare the shared network

If the baileys-api compose is a separate stack, declare the shared network:

```yaml
networks:
  coolify:
    external: true
    name: coolify
```

---

## Step 3 — Verify

After deploying, run from the server's SSH terminal:

```bash
# Check container health
docker ps | grep -E "gluetun|baileys"

# Get the VPN exit IP (replace with your actual gluetun container name)
docker exec <GLUETUN_CONTAINER> wget -qO- https://ipinfo.io/ip

# Compare with the server's real IP
curl -s https://ipinfo.io/ip
```

If the two IPs are **different**, the VPN is working correctly.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Redis client error` / connection timeout on Redis | Baileys starts before VPN is ready | Add `depends_on` with `condition: service_healthy` |
| `Redis client error` / connection refused | Internal Docker traffic blocked by VPN firewall | Add `192.168.0.0/16` to `FIREWALL_OUTBOUND_SUBNETS` |
| `getaddrinfo ENOTFOUND redis` | Docker DNS not working inside VPN | Set `DNS_KEEP_NAMESERVER=on` in gluetun |
| `no server found: ... city sao paulo; owned servers only` | Mullvad has no owned servers in São Paulo | Remove `OWNED_ONLY=yes` from gluetun env |
| `interface address is IPv6 but IPv6 is not supported` | IPv6 address in `WIREGUARD_ADDRESSES` | Use only the IPv4 address (remove the `fc00:...` part) |
| `REDIS_URL` with hardcoded IP (e.g. `172.19.0.2`) | Docker internal IPs change on restart | Always use hostnames (e.g. `redis://redis:6379`) |

---

## VPN Expiration

If the Mullvad subscription expires:
- **WhatsApp stops working** (Baileys can't connect through the VPN).
- **Everything else keeps running** normally (Rails, Sidekiq, Redis, Postgres are not affected).
- To restore: renew Mullvad, or revert the docker-compose changes to bypass the VPN entirely.
