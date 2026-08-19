# Full-stack wrapper: clone the frontend repo, then build the production image.
# Works on Windows / macOS / Linux (no remote Git build-context required).

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
COPY --from=source /src/package.json /src/package-lock.json ./
RUN npm ci
COPY --from=source /src/ ./
RUN npm run build

# ---------- production nginx ----------
FROM nginx:1.27-alpine

RUN rm /etc/nginx/conf.d/default.conf

COPY --from=source /src/docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
