#!/usr/bin/env bash
# Runs as the unprivileged user. Supervises:
#   1. Chrome Remote Desktop host  (registered from .env on first start, or by hand)
#   2. VS Code tunnel               (unless VSCODE_TUNNEL_ENABLED=false)
# Neither needs an inbound port: both dial out to Google / Microsoft.
set -uo pipefail

CRD_SCRIPT=/opt/google/chrome-remote-desktop/chrome-remote-desktop
CRD_CONFIG_DIR="$HOME/.config/chrome-remote-desktop"
COMPUTER_NAME="${COMPUTER_NAME:-$(hostname)}"
POLL_SECONDS=15

crd_pid=""
tunnel_pid=""

log() { echo "[services] $*"; }

cd "$HOME"
mkdir -p "$CRD_CONFIG_DIR"

crd_registered() { compgen -G "$CRD_CONFIG_DIR/host#*.json" >/dev/null; }
alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }

# One-shot registration from the environment (CRD_CODE, CRD_PIN in .env).
# The authorisation code is single-use and expires in minutes, so this only
# runs when nothing is registered yet; afterwards the variables are ignored.
register_crd_from_env() {
    if [ -z "${CRD_PIN:-}" ]; then
        log "CRD_CODE is set but CRD_PIN is empty; cannot register non-interactively"
        return 1
    fi
    log "Registering Chrome Remote Desktop host '$COMPUTER_NAME' from CRD_CODE"
    if DISPLAY= /opt/google/chrome-remote-desktop/start-host \
            --code="$CRD_CODE" \
            --redirect-url="${CRD_REDIRECT_URL:-https://remotedesktop.google.com/_/oauthredirect}" \
            --name="$COMPUTER_NAME" \
            --pin="$CRD_PIN" \
            --no-start; then
        log "Registration succeeded"
    else
        log "Registration FAILED. The code may be used or expired: fetch a fresh one from"
        log "https://remotedesktop.google.com/headless, update CRD_CODE in .env and run:"
        log "  docker compose up -d --force-recreate"
    fi
}

start_crd() {
    log "Starting Chrome Remote Desktop host"
    # --child-process: run directly instead of asking systemd (absent here).
    "$CRD_SCRIPT" --start --child-process &
    crd_pid=$!
}

start_tunnel() {
    log "Starting VS Code tunnel '$COMPUTER_NAME' (first run prints a device-login URL below)"
    code tunnel --accept-server-license-terms --name "$COMPUTER_NAME" &
    tunnel_pid=$!
}

shutdown() {
    log "Stopping services"
    for pid in "$tunnel_pid" "$crd_pid"; do
        alive "$pid" && kill -TERM "$pid" 2>/dev/null
    done
    wait
    exit 0
}
trap shutdown TERM INT

if ! crd_registered; then
    if [ -n "${CRD_CODE:-}" ]; then
        register_crd_from_env
    else
        log "Chrome Remote Desktop is not registered yet. Either set CRD_CODE and CRD_PIN"
        log "in .env and recreate the container, or register by hand (see README)."
    fi
fi

while true; do
    if crd_registered && ! alive "$crd_pid"; then
        start_crd
    fi
    if [ "${VSCODE_TUNNEL_ENABLED:-true}" = "true" ] && ! alive "$tunnel_pid"; then
        start_tunnel
    fi
    sleep "$POLL_SECONDS" &
    wait $!
done
