# Full-stack wrapper: clone the backend repo, then build the production image.
# Works on Windows / macOS / Linux (no remote Git build-context required).

ARG BACKEND_REPO=https://github.com/Mohammad-Alaaei/node-dns-server.git
ARG BACKEND_REF=main

# ---------- fetch source ----------
FROM alpine:3.20 AS source
ARG BACKEND_REPO
ARG BACKEND_REF
RUN apk add --no-cache git \
 && git clone --depth 1 --branch "${BACKEND_REF}" "${BACKEND_REPO}" /src

# ---------- production image ----------
FROM node:22-alpine

RUN apk add --no-cache tini

WORKDIR /app

# Dependencies first (better layer cache when only app code changes)
COPY --from=source /src/package.json /src/package-lock.json ./
RUN npm ci --omit=dev \
 && npm install sequelize-cli --no-save \
 && npm cache clean --force

# Full source
COPY --from=source /src/ ./

RUN mkdir -p /app/logs /app/data \
 && chmod +x /app/docker/entrypoint.sh

ENV NODE_ENV=production
ENV LOG_DIR=/app/logs

# 53/udp is used for both IPv4 and IPv6 DNS inside the container
EXPOSE 53/udp 3000

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/app/docker/entrypoint.sh"]
