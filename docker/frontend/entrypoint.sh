#!/bin/sh
set -e

HTTPS_ENABLED="${HTTPS_ENABLED:-true}"
SSL_MODE="${SSL_MODE:-selfsigned}"
SSL_CERT_HOSTS="${SSL_CERT_HOSTS:-localhost,127.0.0.1}"
CERT_DIR="${CERT_DIR:-/etc/nginx/certs}"
CONF_DIR="/etc/nginx/conf.d"
CONF_FILE="${CONF_DIR}/default.conf"

# Normalize booleans
case "$(echo "$HTTPS_ENABLED" | tr '[:upper:]' '[:lower:]')" in
  1|true|yes|on) HTTPS_ENABLED=true ;;
  *) HTTPS_ENABLED=false ;;
esac

case "$(echo "$SSL_MODE" | tr '[:upper:]' '[:lower:]')" in
  off|disabled|none) SSL_MODE=off ;;
  custom) SSL_MODE=custom ;;
  *) SSL_MODE=selfsigned ;;
esac

if [ "$HTTPS_ENABLED" = "false" ]; then
  SSL_MODE=off
fi

mkdir -p "$CERT_DIR" "$CONF_DIR"

write_http_server() {
  cat > "$CONF_FILE" <<'NGINX'
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript image/svg+xml;
    gzip_min_length 256;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    location /api/ {
        proxy_pass http://backend:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Authorization $http_authorization;
        proxy_pass_header Authorization;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location / {
        try_files $uri $uri/ /index.html;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 7d;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }
}
NGINX
}

write_https_server() {
  cat > "$CONF_FILE" <<'NGINX'
# Redirect all HTTP to HTTPS
server {
    listen 80;
    server_name _;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    ssl_certificate     /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript image/svg+xml;
    gzip_min_length 256;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    location /api/ {
        proxy_pass http://backend:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Authorization $http_authorization;
        proxy_pass_header Authorization;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location / {
        try_files $uri $uri/ /index.html;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 7d;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }
}
NGINX
}

generate_selfsigned() {
  if [ -f "$CERT_DIR/fullchain.pem" ] && [ -f "$CERT_DIR/privkey.pem" ]; then
    echo "[ssl] Using existing certificates in $CERT_DIR"
    return 0
  fi

  echo "[ssl] Generating self-signed certificate for: $SSL_CERT_HOSTS"
  FIRST=$(echo "$SSL_CERT_HOSTS" | cut -d',' -f1 | tr -d ' ')
  SAN=""
  OLD_IFS=$IFS
  IFS=','
  for host in $SSL_CERT_HOSTS; do
    host=$(echo "$host" | tr -d ' ')
    [ -z "$host" ] && continue
    case "$host" in
      *[0-9].*[0-9].*[0-9].*[0-9]*)
        # rough IPv4
        if [ -n "$SAN" ]; then SAN="$SAN,IP:$host"; else SAN="IP:$host"; fi
        ;;
      *:*)
        if [ -n "$SAN" ]; then SAN="$SAN,IP:$host"; else SAN="IP:$host"; fi
        ;;
      *)
        if [ -n "$SAN" ]; then SAN="$SAN,DNS:$host"; else SAN="DNS:$host"; fi
        ;;
    esac
  done
  IFS=$OLD_IFS

  # Always include localhost / 127.0.0.1 for local access
  case ",$SAN," in
    *,DNS:localhost,*) ;;
    *) SAN="${SAN:+$SAN,}DNS:localhost" ;;
  esac
  case ",$SAN," in
    *,IP:127.0.0.1,*) ;;
    *) SAN="${SAN:+$SAN,}IP:127.0.0.1" ;;
  esac

  openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
    -keyout "$CERT_DIR/privkey.pem" \
    -out "$CERT_DIR/fullchain.pem" \
    -subj "/CN=${FIRST}" \
    -addext "subjectAltName=${SAN}"

  echo "[ssl] Self-signed certificate written to $CERT_DIR"
}

case "$SSL_MODE" in
  off)
    echo "[ssl] HTTPS disabled (HTTPS_ENABLED=$HTTPS_ENABLED SSL_MODE=$SSL_MODE)"
    write_http_server
    ;;
  custom)
    if [ ! -f "$CERT_DIR/fullchain.pem" ] || [ ! -f "$CERT_DIR/privkey.pem" ]; then
      echo "[ssl] ERROR: SSL_MODE=custom requires $CERT_DIR/fullchain.pem and privkey.pem" >&2
      exit 1
    fi
    echo "[ssl] Using custom certificates from $CERT_DIR"
    write_https_server
    ;;
  selfsigned)
    generate_selfsigned
    write_https_server
    ;;
esac

echo "[ssl] Starting nginx (HTTPS_ENABLED=$HTTPS_ENABLED SSL_MODE=$SSL_MODE)"
exec nginx -g 'daemon off;'
