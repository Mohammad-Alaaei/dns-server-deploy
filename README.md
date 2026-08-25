# DNS Stack (full Docker compose)

Runs the complete product:

| Service        | Role                                             |
| -------------- | ------------------------------------------------ |
| **db**         | MySQL 8                                          |
| **backend**    | Custom DNS server + REST API (`node-dns-server`) |
| **frontend**   | Admin UI (nginx + SPA)                           |
| **phpmyadmin** | DB UI (optional ops)                             |

Application sources are **not** required next to this compose file. Thin Dockerfiles under `docker/{backend,frontend}` **clone** the app repos from GitHub at image build time.

- Backend: https://github.com/Mohammad-Alaaei/node-dns-server.git
- Frontend: https://github.com/Mohammad-Alaaei/dns-server-frontend.git

Override clone targets with `BACKEND_REPO` / `BACKEND_REF` and `FRONTEND_REPO` / `FRONTEND_REF`.

---

## Quick start

```bash
cp .env.example .env          # edit secrets and TLS options if needed
docker compose up -d --build
```

**Default ports**

| Port       | Service                                                |
| ---------- | ------------------------------------------------------ |
| **80**     | Admin UI HTTP (redirects to HTTPS when TLS is enabled) |
| **443**    | Admin UI HTTPS                                         |
| **8080**   | phpMyAdmin                                             |
| **53/udp** | DNS (IPv4 + IPv6)                                      |

Default TLS: **HTTPS enabled**, **self-signed** certificates. Open **https://localhost** (browser warning on self-signed is expected).

---

## TLS / HTTPS (frontend nginx)

TLS terminates on the **frontend** container only. The backend API stays on the internal Docker network over HTTP; nginx proxies `/api` and sets `X-Forwarded-Proto`.

Configuration is **runtime** environment on the `frontend` service (see `.env.example`). No SPA rebuild is required to change TLS mode.

### Environment variables

| Variable         | Default               | Description                                                                            |
| ---------------- | --------------------- | -------------------------------------------------------------------------------------- |
| `HTTPS_ENABLED`  | `true`                | Master switch. `false` → HTTP only on port 80.                                         |
| `SSL_MODE`       | `selfsigned`          | `selfsigned` \| `custom` \| `off`                                                      |
| `SSL_CERT_HOSTS` | `localhost,127.0.0.1` | SAN list for generated self-signed certificates (comma-separated DNS names and/or IPs) |
| `SSL_CERTS_DIR`  | `./certs`             | Host path mounted at `/etc/nginx/certs` inside the frontend container                  |

When `HTTPS_ENABLED=false`, `SSL_MODE` is forced off regardless of its value.

### Mode matrix

| `HTTPS_ENABLED` | `SSL_MODE`   | Behaviour                                                                                                 |
| --------------- | ------------ | --------------------------------------------------------------------------------------------------------- |
| `true`          | `selfsigned` | Port **443** with self-signed cert (generated if missing). Port **80** redirects to HTTPS.                |
| `true`          | `custom`     | Port **443** using `fullchain.pem` + `privkey.pem` from the certs volume. Port **80** redirects to HTTPS. |
| `true`          | `off`        | HTTP only on port **80**.                                                                                 |
| `false`         | _(ignored)_  | HTTP only on port **80**.                                                                                 |

### Examples

```bash
# Default: HTTPS + self-signed (localhost / 127.0.0.1)
docker compose up -d --build

# Self-signed for your LAN name or IP
SSL_CERT_HOSTS=dns.example.lan,192.168.1.10 docker compose up -d --build

# Production-like custom certificates
# 1. Place files:
#      ./certs/fullchain.pem
#      ./certs/privkey.pem
# 2. Run:
SSL_MODE=custom docker compose up -d --build

# Lab / no TLS
HTTPS_ENABLED=false docker compose up -d --build
```

### Certificate volume

```yaml
# compose mounts:
#   ${SSL_CERTS_DIR:-./certs} → /etc/nginx/certs
```

- **selfsigned**: entrypoint creates `fullchain.pem` and `privkey.pem` when absent; files remain on the host under `SSL_CERTS_DIR` across restarts.
- **custom**: both PEM files must exist before start; otherwise the frontend container exits with an error.

Implementation lives in:

- `docker/frontend/entrypoint.sh` (copied into the image; authoritative for TLS in this stack)
- Frontend repo `docker/entrypoint.sh` (used when building the UI image from that repo alone)

### CORS and HTTPS

If the browser origin is `https://…` and the API is not same-origin, ensure `API_CORS_ORIGINS` includes those origins (`.env.example` already lists `https://localhost` and `https://127.0.0.1`). With the default nginx `/api` proxy, UI and API share the same host and CORS is usually unused.

---

## Password encryption (not the same as TLS)

Login, change-password, and create-user **always** send RSA-OAEP ciphertext (SHA-256, base64) from the Admin UI (`node-forge`), using the backend public key from `GET /api/auth/public-key`.

| Layer                                  | Purpose                                                                            |
| -------------------------------------- | ---------------------------------------------------------------------------------- |
| **TLS** (`HTTPS_ENABLED` / `SSL_MODE`) | Encrypt the whole HTTP session browser ↔ nginx                                     |
| **RSA-OAEP** (frontend crypto)         | Encrypt passwords before they leave the browser — **still used when HTTPS is off** |

Disabling TLS does **not** disable password encryption.

---

## Other useful env

See `.env.example` for MySQL, JWT, admin bootstrap, DNS cache levels, and Git repo/ref overrides.

```bash
# Pin frontend/backend git refs
FRONTEND_REF=main
BACKEND_REF=main
```

---

## Frontend-only compose

To run only the Admin UI image, use the compose file inside the frontend repository (`dns-admin-ui` / dns-server-frontend). TLS variables and behaviour match this document; see that repo’s README for standalone API URL build args (`VITE_API_BASE_URL`).
