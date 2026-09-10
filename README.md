# DNS Stack (full Docker deploy)

Runs the complete product by **cloning** the app repos from GitHub at image build time. You do **not** need the backend/frontend source trees next to this folder.

| Service | Role |
| -------- | ---- |
| **db** | MySQL 8.4 (Linux) or Alpine MariaDB (Pi) |
| **backend** | Custom DNS server + REST API (`node-dns-server`) |
| **frontend** | Admin UI (nginx + SPA) |
| **phpmyadmin** | DB UI (Linux variant only) |

- Backend: https://github.com/Mohammad-Alaaei/node-dns-server.git
- Frontend: https://github.com/Mohammad-Alaaei/dns-server-frontend.git

Override with `BACKEND_REPO` / `BACKEND_REF` and `FRONTEND_REPO` / `FRONTEND_REF`.

---

## Quick start

```bash
cp .env.example .env          # edit secrets / TLS if needed
./deploy.sh                   # interactive menu (Windows Git Bash, Linux, Pi)
```

Or non-interactive:

```bash
./deploy.sh soft --platform linux --full
./deploy.sh soft --platform pi --frontend
./deploy.sh hard --platform pi
./deploy.sh fresh --platform linux
./deploy.sh status
./deploy.sh stop
```

### Update modes

| Mode | What it does |
| ---- | ------------ |
| **Soft** | Forces a fresh git clone (`CACHEBUST`). Reuses npm layers when `package-lock.json` is unchanged. Uses BuildKit npm cache so even dependency changes stay relatively cheap. |
| **Hard** | `--no-cache --pull` — re-downloads base images and all packages. |
| **Fresh** | `down -v` (deletes volumes) + Hard rebuild. |

### Platforms

| Folder | Target |
| ------ | ------ |
| `linux/` | Windows, Linux, macOS (MySQL 8.4 + phpMyAdmin, alpine Node builds) |
| `pi/` | Raspberry Pi (Alpine MariaDB, bookworm Node builds for frontend) |

Backend Dockerfile is the same on both platforms.

### Default ports

| Port | Service |
| ---- | ------- |
| **80** | Admin UI HTTP (redirects to HTTPS when TLS enabled) |
| **443** | Admin UI HTTPS |
| **8080** | phpMyAdmin (Linux only) |
| **53/udp** | DNS (IPv4 + IPv6) |

Default TLS: HTTPS on, self-signed certs. Open https://localhost (browser warning expected).

---

## TLS / HTTPS (frontend nginx)

TLS terminates on the **frontend** container. Backend stays on the internal network over HTTP; nginx proxies `/api`.

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `HTTPS_ENABLED` | `true` | Master switch |
| `SSL_MODE` | `selfsigned` | `selfsigned` / `custom` / `off` |
| `SSL_CERT_HOSTS` | `localhost,127.0.0.1` | SAN list for self-signed certs |
| `SSL_CERTS_DIR` | repo-root `certs/` | Host path mounted at `/etc/nginx/certs` |

`deploy.sh` always points `SSL_CERTS_DIR` at the repo-root `certs/` folder.

---

## Manual compose (without the menu)

```bash
# Linux / Windows
docker compose -f linux/docker-compose.yml --project-directory linux up -d --build

# Raspberry Pi
docker compose -f pi/docker-compose.yml --project-directory pi up -d --build
```

For Soft-style rebuild without the script:

```bash
docker compose -f pi/docker-compose.yml --project-directory pi build \
  --build-arg CACHEBUST=$(date +%s) frontend
```

---

## Layout

```
full-deploy/
├── deploy.sh              # interactive + CLI entrypoint
├── .env.example
├── certs/                 # TLS certs (shared)
├── linux/
│   ├── docker-compose.yml
│   └── docker/{backend,frontend}/
└── pi/
    ├── docker-compose.yml
    └── docker/{backend,frontend}/
```
