# dns-server-deploy

A full-stack setup of DNS server for docker

## Quick Setup

```bash
cp .env.example .env        # edit secrets
docker compose up -d --build
```

## Rebuild / update

```bash
docker compose up -d --build
```

Logs and the seed marker survive the rebuild.  
To wipe everything (including the database):

```bash
docker compose down -v
```
