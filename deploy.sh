#!/usr/bin/env bash
# DNS Stack deploy menu — works on Windows (Git Bash), Linux, and Raspberry Pi.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# Ensure .env exists
if [ ! -f .env ]; then
  if [ -f .env.example ]; then
    cp .env.example .env
    echo "Created .env from .env.example — edit secrets if needed."
  else
    echo "WARNING: no .env or .env.example found"
  fi
fi

# Always point certs at the repo-root certs/ folder (absolute path is safest)
export SSL_CERTS_DIR="${SSL_CERTS_DIR:-$ROOT/certs}"
mkdir -p "$SSL_CERTS_DIR"

# ---------- helpers ----------
is_raspberry_pi() {
  if [ -f /proc/device-tree/model ] 2>/dev/null; then
    grep -qi "raspberry" /proc/device-tree/model 2>/dev/null && return 0
  fi
  case "$(uname -m 2>/dev/null || echo unknown)" in
    armv7l|aarch64|arm64) return 0 ;;
  esac
  return 1
}

detect_platform() {
  if is_raspberry_pi; then
    echo "pi"
  else
    echo "linux"
  fi
}

platform_label() {
  case "$1" in
    pi) echo "Raspberry Pi" ;;
    *)  echo "Windows / Linux / macOS" ;;
  esac
}

# Space-separated service names for the selected platform
platform_services() {
  case "${1:-linux}" in
    pi) echo "db backend frontend" ;;
    *)  echo "db backend frontend phpmyadmin" ;;
  esac
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    echo "ERROR: neither 'docker compose' nor 'docker-compose' found" >&2
    exit 1
  fi
}

run_compose() {
  local file="$1"
  shift
  compose_cmd -f "$file" --project-directory "$(dirname "$file")" --env-file "$ROOT/.env" "$@"
}

ask() {
  printf "%s" "$1"
  read -r REPLY
}

confirm() {
  ask "$1 [y/N]: "
  case "$REPLY" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------- menus ----------
choose_platform() {
  local detected
  detected="$(detect_platform)"
  echo ""
  echo "Platform (detected: $(platform_label "$detected"))"
  echo "  1) Windows / Linux / macOS"
  echo "  2) Raspberry Pi"
  ask "Choose [1-2] (default depends on detection): "
  case "$REPLY" in
    1) PLATFORM=linux ;;
    2) PLATFORM=pi ;;
    *) PLATFORM="$detected" ;;
  esac
  COMPOSE_FILE="$ROOT/$PLATFORM/docker-compose.yml"
  if [ ! -f "$COMPOSE_FILE" ]; then
    echo "ERROR: missing $COMPOSE_FILE" >&2
    exit 1
  fi
  echo "→ Using $(platform_label "$PLATFORM")  ($COMPOSE_FILE)"
}

# For Soft/Hard update targets (buildable app services)
choose_services() {
  echo ""
  echo "Services"
  echo "  1) Full stack"
  echo "  2) Backend only"
  echo "  3) Frontend only"
  ask "Choose [1-3]: "
  case "$REPLY" in
    2) SERVICES="backend" ;;
    3) SERVICES="frontend" ;;
    *) SERVICES="" ;;
  esac
}

# For Start/Stop: all + each service available on the platform
# Sets RUNTIME_SERVICES to either empty (all) or one service name
choose_runtime_service() {
  local action="$1"
  local svc_list i n
  svc_list="$(platform_services "$PLATFORM")"
  echo ""
  echo "$action which service?"
  echo "  1) All"
  i=2
  for s in $svc_list; do
    echo "  $i) $s"
    i=$((i + 1))
  done
  ask "Choose: "
  case "$REPLY" in
    1|"") RUNTIME_SERVICES="" ;;
    *)
      n=2
      RUNTIME_SERVICES=""
      for s in $svc_list; do
        if [ "$REPLY" = "$n" ]; then
          RUNTIME_SERVICES="$s"
          break
        fi
        n=$((n + 1))
      done
      if [ -z "$RUNTIME_SERVICES" ] && [ "$REPLY" != "1" ]; then
        echo "Invalid choice."
        RUNTIME_SERVICES=""
        return 1
      fi
      ;;
  esac
  return 0
}

do_soft_update() {
  choose_platform
  choose_services
  local bust
  bust="$(date +%s 2>/dev/null || echo 1)"
  echo ""
  echo "=== Soft Update (CACHEBUST=$bust) ==="
  echo "Re-clones source from GitHub; reuses npm layers when package-lock is unchanged."
  if [ -n "$SERVICES" ]; then
    CACHEBUST="$bust" run_compose "$COMPOSE_FILE" build --build-arg "CACHEBUST=$bust" $SERVICES
    run_compose "$COMPOSE_FILE" up -d $SERVICES
  else
    CACHEBUST="$bust" run_compose "$COMPOSE_FILE" build --build-arg "CACHEBUST=$bust"
    run_compose "$COMPOSE_FILE" up -d
  fi
  echo "Done."
}

do_hard_update() {
  choose_platform
  choose_services
  echo ""
  echo "=== Hard Update (--no-cache --pull) ==="
  echo "Re-downloads base images and all packages."
  if [ -n "$SERVICES" ]; then
    run_compose "$COMPOSE_FILE" build --no-cache --pull $SERVICES
    run_compose "$COMPOSE_FILE" up -d $SERVICES
  else
    run_compose "$COMPOSE_FILE" build --no-cache --pull
    run_compose "$COMPOSE_FILE" up -d
  fi
  echo "Done."
}

do_fresh_install() {
  choose_platform
  echo ""
  echo "=== Fresh Install ==="
  echo "This will STOP containers and DELETE volumes (database data, logs, seed marker)."
  if ! confirm "Continue?"; then
    echo "Cancelled."
    return
  fi
  run_compose "$COMPOSE_FILE" down -v --remove-orphans || true
  run_compose "$COMPOSE_FILE" build --no-cache --pull
  run_compose "$COMPOSE_FILE" up -d
  echo "Done."
}

do_status() {
  choose_platform
  echo ""
  run_compose "$COMPOSE_FILE" ps
  echo ""
  ask "Show recent logs? [y/N]: "
  case "$REPLY" in
    y|Y|yes|YES)
      ask "Service name (empty = all): "
      if [ -n "$REPLY" ]; then
        run_compose "$COMPOSE_FILE" logs --tail=80 "$REPLY"
      else
        run_compose "$COMPOSE_FILE" logs --tail=40
      fi
      ;;
  esac
}

do_stop_service() {
  choose_platform
  if ! choose_runtime_service "Stop"; then
    return
  fi
  echo ""
  if [ -z "$RUNTIME_SERVICES" ]; then
    echo "Stopping all services..."
    run_compose "$COMPOSE_FILE" stop
  else
    echo "Stopping $RUNTIME_SERVICES..."
    run_compose "$COMPOSE_FILE" stop $RUNTIME_SERVICES
  fi
  echo "Done."
}

do_start_service() {
  choose_platform
  if ! choose_runtime_service "Start"; then
    return
  fi
  echo ""
  # up -d starts existing containers or creates them if missing
  if [ -z "$RUNTIME_SERVICES" ]; then
    echo "Starting all services..."
    run_compose "$COMPOSE_FILE" up -d
  else
    echo "Starting $RUNTIME_SERVICES..."
    run_compose "$COMPOSE_FILE" up -d $RUNTIME_SERVICES
  fi
  echo "Done."
}

# ---------- non-interactive CLI ----------
usage() {
  cat <<EOF
Usage: $0 [command] [options]

Interactive (no args):
  $0

Commands:
  soft  [--platform linux|pi] [--backend|--frontend|--full]
  hard  [--platform linux|pi] [--backend|--frontend|--full]
  fresh [--platform linux|pi]
  status [--platform linux|pi]
  stop  [--platform linux|pi] [--all|--db|--backend|--frontend|--phpmyadmin]
  start [--platform linux|pi] [--all|--db|--backend|--frontend|--phpmyadmin]

Examples:
  $0 soft --platform pi --frontend
  $0 hard --full
  $0 stop --platform pi --backend
  $0 start --platform pi --all
  $0 fresh --platform linux
EOF
}

parse_and_run() {
  local cmd="$1"
  shift || true
  PLATFORM=""
  SERVICES=""
  RUNTIME_SERVICES=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --platform)
        PLATFORM="$2"
        shift 2
        ;;
      --platform=*)
        PLATFORM="${1#*=}"
        shift
        ;;
      --backend)
        SERVICES="backend"
        RUNTIME_SERVICES="backend"
        shift
        ;;
      --frontend)
        SERVICES="frontend"
        RUNTIME_SERVICES="frontend"
        shift
        ;;
      --db)
        RUNTIME_SERVICES="db"
        shift
        ;;
      --phpmyadmin)
        RUNTIME_SERVICES="phpmyadmin"
        shift
        ;;
      --full|--all)
        SERVICES=""
        RUNTIME_SERVICES=""
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  if [ -z "$PLATFORM" ]; then
    PLATFORM="$(detect_platform)"
  fi
  case "$PLATFORM" in
    linux|pi) ;;
    *) echo "Invalid platform: $PLATFORM (use linux or pi)" >&2; exit 1 ;;
  esac
  COMPOSE_FILE="$ROOT/$PLATFORM/docker-compose.yml"
  if [ ! -f "$COMPOSE_FILE" ]; then
    echo "ERROR: missing $COMPOSE_FILE" >&2
    exit 1
  fi

  case "$cmd" in
    soft)
      local bust
      bust="$(date +%s 2>/dev/null || echo 1)"
      echo "Soft update ($(platform_label "$PLATFORM")) CACHEBUST=$bust"
      if [ -n "$SERVICES" ]; then
        CACHEBUST="$bust" run_compose "$COMPOSE_FILE" build --build-arg "CACHEBUST=$bust" $SERVICES
        run_compose "$COMPOSE_FILE" up -d $SERVICES
      else
        CACHEBUST="$bust" run_compose "$COMPOSE_FILE" build --build-arg "CACHEBUST=$bust"
        run_compose "$COMPOSE_FILE" up -d
      fi
      ;;
    hard)
      echo "Hard update ($(platform_label "$PLATFORM"))"
      if [ -n "$SERVICES" ]; then
        run_compose "$COMPOSE_FILE" build --no-cache --pull $SERVICES
        run_compose "$COMPOSE_FILE" up -d $SERVICES
      else
        run_compose "$COMPOSE_FILE" build --no-cache --pull
        run_compose "$COMPOSE_FILE" up -d
      fi
      ;;
    fresh)
      echo "Fresh install ($(platform_label "$PLATFORM")) — volumes will be deleted"
      if ! confirm "Continue?"; then echo "Cancelled."; exit 0; fi
      run_compose "$COMPOSE_FILE" down -v --remove-orphans || true
      run_compose "$COMPOSE_FILE" build --no-cache --pull
      run_compose "$COMPOSE_FILE" up -d
      ;;
    status)
      run_compose "$COMPOSE_FILE" ps
      ;;
    stop)
      if [ -z "$RUNTIME_SERVICES" ]; then
        echo "Stopping all services ($(platform_label "$PLATFORM"))..."
        run_compose "$COMPOSE_FILE" stop
      else
        echo "Stopping $RUNTIME_SERVICES ($(platform_label "$PLATFORM"))..."
        run_compose "$COMPOSE_FILE" stop $RUNTIME_SERVICES
      fi
      ;;
    start)
      if [ -z "$RUNTIME_SERVICES" ]; then
        echo "Starting all services ($(platform_label "$PLATFORM"))..."
        run_compose "$COMPOSE_FILE" up -d
      else
        echo "Starting $RUNTIME_SERVICES ($(platform_label "$PLATFORM"))..."
        run_compose "$COMPOSE_FILE" up -d $RUNTIME_SERVICES
      fi
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

# ---------- main ----------
if [ $# -gt 0 ]; then
  parse_and_run "$@"
  exit 0
fi

while true; do
  echo ""
  echo "========================================"
  echo "  DNS Stack Deploy"
  echo "========================================"
  echo "  1) Soft Update   (recommended daily)"
  echo "  2) Hard Update   (full re-download)"
  echo "  3) Fresh Install (delete volumes)"
  echo "  4) Status / Logs"
  echo "  5) Stop service"
  echo "  6) Start service"
  echo "  0) Exit"
  echo "========================================"
  ask "Choose [0-6]: "
  case "$REPLY" in
    1) do_soft_update ;;
    2) do_hard_update ;;
    3) do_fresh_install ;;
    4) do_status ;;
    5) do_stop_service ;;
    6) do_start_service ;;
    0|q|Q) echo "Bye."; exit 0 ;;
    *) echo "Invalid choice." ;;
  esac
done
