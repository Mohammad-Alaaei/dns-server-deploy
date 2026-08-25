# Full-stack wrapper: clone the frontend repo, then build the production image.
# TLS is controlled by entrypoint.sh in THIS directory (not by the cloned repo alone).

ARG FRONTEND_REPO=https://github.com/Mohammad-Alaaei/dns-server-frontend.git
ARG FRONTEND_REF=main
ARG VITE_API_BASE_URL=

# ---------- fetch source ----------
FROM node:22-bookworm AS source
ARG FRONTEND_REPO
ARG FRONTEND_REF
RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/* \
    && git clone --depth 1 --branch "${FRONTEND_REF}" "${FRONTEND_REPO}" /src

# ---------- build SPA ----------
FROM node:22-bookworm AS builder
ARG VITE_API_BASE_URL
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL

WORKDIR /app
COPY --from=source /src/package.json /src/package-lock.json* ./
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi
COPY --from=source /src/ ./
RUN npm run build

# ---------- production nginx ----------
FROM nginx:1.27-alpine

RUN apk add --no-cache openssl \
    && rm -f /etc/nginx/conf.d/default.conf \
    && mkdir -p /etc/nginx/certs

# Authoritative TLS entrypoint from the deploy/stack repo build context
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
    && head -1 /entrypoint.sh | grep -q '^#!' \
    && echo "TLS entrypoint installed OK"

# Static HTTP fallback only (entrypoint overwrites at runtime)
COPY --from=source /src/docker/nginx.conf /etc/nginx/conf.d/default.conf

COPY --from=builder /app/dist /usr/share/nginx/html

ENV HTTPS_ENABLED=true \
    SSL_MODE=selfsigned \
    SSL_CERT_HOSTS=localhost,127.0.0.1

EXPOSE 80 443
