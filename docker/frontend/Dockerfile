# Full-stack wrapper: clone the frontend repo, then build the production image.
# Works on Windows / macOS / Linux (no remote Git build-context required).

ARG FRONTEND_REPO=https://github.com/Mohammad-Alaaei/dns-server-frontend.git
ARG FRONTEND_REF=main
ARG VITE_API_BASE_URL=

# ---------- fetch source ----------
FROM alpine:3.20 AS source
ARG FRONTEND_REPO
ARG FRONTEND_REF
RUN apk add --no-cache git \
 && git clone --depth 1 --branch "${FRONTEND_REF}" "${FRONTEND_REPO}" /src

# ---------- build SPA ----------
FROM node:22-alpine AS builder
ARG VITE_API_BASE_URL
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL

WORKDIR /app
COPY --from=source /src/package.json /src/package-lock.json ./
RUN npm ci
COPY --from=source /src/ ./
RUN npm run build

# ---------- production nginx ----------
FROM nginx:1.27-alpine

RUN apk add --no-cache openssl \
 && rm -f /etc/nginx/conf.d/default.conf \
 && mkdir -p /etc/nginx/certs

# SSL entrypoint from this stack repo (authoritative for TLS behaviour)
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Optional static fallback from cloned frontend (overwritten at runtime by entrypoint)
COPY --from=source /src/docker/nginx.conf /etc/nginx/conf.d/default.conf

COPY --from=builder /app/dist /usr/share/nginx/html

ENV HTTPS_ENABLED=true \
    SSL_MODE=selfsigned \
    SSL_CERT_HOSTS=localhost,127.0.0.1

EXPOSE 80 443

ENTRYPOINT ["/entrypoint.sh"]
